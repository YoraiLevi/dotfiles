const { Plugin, Notice, TFile } = require('obsidian');

const DEFAULT_WATCHED_FOLDERS = ['00 INBOX', '01 PROJET', '02 CAPS'];
const DEFAULT_INTERVAL_MS = 3000;
const DEFAULT_TIMEOUT_MS = 1000;
const DEBUG = false; // Set to true for verbose console logging

function log(...args) {
    if (DEBUG) console.log('[AutoRefresh]', ...args);
}

/**
 * Auto Refresh Explorer — Injects externally-created files into Obsidian's index.
 *
 * When Syncthing (or any external tool) drops new files into the vault,
 * Obsidian's desktop file watcher often misses them. This plugin detects
 * folder changes via low-cost adapter.stat() polling and manually
 * creates TFile objects + fires vault 'create' events so the file explorer
 * and metadata cache pick them up instantly.
 */
module.exports = class AutoRefreshExplorerPlugin extends Plugin {
    onload() {
        log('Loaded');

        this.pollInterval = null;
        this.mtimeStore = new Map();
        this.isRefreshing = new Map();
        this.watchedFolders = DEFAULT_WATCHED_FOLDERS;
        this.scanIntervalMs = DEFAULT_INTERVAL_MS;
        this.listTimeoutMs = DEFAULT_TIMEOUT_MS;

        const init = () => {
            this.initMtimeBaseline(this.watchedFolders).then(() => {
                this.pollInterval = window.setInterval(
                    () => this.scanFolders(),
                    this.scanIntervalMs
                );
                this.registerInterval(this.pollInterval);
                new Notice('Auto Refresh: active');
            });
        };

        if (this.app.workspace && typeof this.app.workspace.onLayoutReady === 'function') {
            this.app.workspace.onLayoutReady(init);
        } else {
            window.setTimeout(init, 2000);
        }

        this.addCommand({
            id: 'refresh-explorer-now',
            name: 'Refresh file explorer now',
            callback: () => this.refreshAll()
        });
    }

    /** ── Polling ─────────────────────────────────────────────── */

    async scanFolders() {
        for (const folderPath of this.watchedFolders) {
            try {
                const changed = await this.checkMtimeChange(folderPath);
                if (changed) {
                    log('Change detected:', folderPath);
                    await this.handleFolderChange(folderPath);
                }
            } catch (e) {
                log('Scan error:', e.message);
            }
        }
    }

    async initMtimeBaseline(folders) {
        for (const folderPath of folders) {
            try {
                const stat = await this.app.vault.adapter.stat(folderPath);
                if (stat?.mtime) {
                    this.mtimeStore.set(folderPath, stat.mtime);
                }
            } catch {
                this.mtimeStore.set(folderPath, Date.now());
            }
        }
    }

    async checkMtimeChange(folderPath) {
        const stat = await this.app.vault.adapter.stat(folderPath);
        if (!stat?.mtime) return false;

        const previous = this.mtimeStore.get(folderPath);
        const current  = stat.mtime;

        if (previous === undefined) {
            this.mtimeStore.set(folderPath, current);
            return false;
        }
        if (current !== previous) {
            this.mtimeStore.set(folderPath, current);
            return true;
        }
        return false;
    }

    async updateMtimeBaseline(folderPath) {
        try {
            const stat = await this.app.vault.adapter.stat(folderPath);
            if (stat?.mtime) this.mtimeStore.set(folderPath, stat.mtime);
        } catch { /* ignore */ }
    }

    /** ── Core handler ──────────────────────────────────────── */

    async refreshAll() {
        for (const folderPath of this.watchedFolders) {
            await this.handleFolderChange(folderPath);
        }
        new Notice('File explorer refreshed');
    }

    async handleFolderChange(folderPath) {
        if (this.isRefreshing.get(folderPath)) return;
        this.isRefreshing.set(folderPath, true);

        try {
            const newFiles = await this.findNewFiles(folderPath);

            if (newFiles.length > 0) {
                log('Found', newFiles.length, 'new file(s) in', folderPath);
                for (const filePath of newFiles) {
                    await this.injectFile(filePath, folderPath);
                }
                this.forceFileExplorerUpdate(folderPath);
            } else {
                log('No new files in', folderPath);
            }
        } catch (e) {
            log('Handler error:', e.message);
        } finally {
            this.isRefreshing.set(folderPath, false);
            await this.updateMtimeBaseline(folderPath);
        }
    }

    /** ── File discovery ────────────────────────────────────── */

    async findNewFiles(folderPath) {
        return new Promise((resolve) => {
            const timer = setTimeout(() => resolve([]), this.listTimeoutMs);

            this._doFindNewFiles(folderPath)
                .then(files => { clearTimeout(timer); resolve(files); })
                .catch(() => { clearTimeout(timer); resolve([]); });
        });
    }

    async _doFindNewFiles(folderPath) {
        const listing = await this.app.vault.adapter.list(folderPath);
        const newFiles = [];

        for (const item of listing.files) {
            const path = item.replace(/\\/g, '/');
            const name = path.split('/').pop();

            // Only .md, skip hidden & sentinel artefacts
            if (!name.endsWith('.md') || name.startsWith('.') || name.startsWith('autorefresh')) {
                continue;
            }

            if (!this.app.vault.getAbstractFileByPath(path)) {
                newFiles.push(path);
            }
        }
        return newFiles;
    }

    /** ── Injection ─────────────────────────────────────────── */

    async injectFile(filePath, folderPath) {
        log('Injecting:', filePath);

        const parent = this.app.vault.getAbstractFileByPath(folderPath);
        if (!parent) {
            log('Parent missing:', folderPath);
            return;
        }

        try {
            const stat = await this.app.vault.adapter.stat(filePath);
            const fileStat = stat || { ctime: Date.now(), mtime: Date.now(), size: 0 };

            // 1. Build a real TFile with the correct parent
            const tFile = new TFile(this.app.vault, filePath, fileStat);
            Object.defineProperty(tFile, 'parent', { value: parent, writable: true });

            // 2. Fire vault 'create' → file explorer + metadata cache react
            this.app.vault.trigger('create', tFile);
            log('Injected:', filePath);

            // 3. Push into metadata cache
            try {
                const content = await this.app.vault.adapter.read(filePath);
                this.app.metadataCache.trigger('resolve', filePath, content, false);
            } catch { /* not yet readable */ }

            // 4. Extra metadata cache nudge
            if (typeof this.app.metadataCache?.onCreate === 'function') {
                this.app.metadataCache.onCreate(tFile);
            }
        } catch (e) {
            log('Injection error:', e.message);
        }
    }

    /** ── UI refresh ────────────────────────────────────────── */

    forceFileExplorerUpdate(folderPath) {
        try {
            // Workspace-level nudge
            this.app.workspace?.requestLayoutRefresh?.();
            this.app.workspace?.trigger?.('layout-change');

            // Leaf-level nudge
            const leaves = this.app.workspace.getLeavesOfType('file-explorer');
            for (const leaf of leaves) {
                const view = leaf.view;
                if (!view) continue;

                view.requestUpdate?.();
                view.update?.();
                view.fileItems?.[folderPath]?.update?.();
            }

            log('UI refresh for:', folderPath);
        } catch (e) {
            log('UI refresh error:', e.message);
        }
    }

    /** ── Lifecycle ─────────────────────────────────────────── */

    onunload() {
        log('Unloaded');
        if (this.pollInterval) {
            window.clearInterval(this.pollInterval);
        }
    }
}

/* nosourcemap */