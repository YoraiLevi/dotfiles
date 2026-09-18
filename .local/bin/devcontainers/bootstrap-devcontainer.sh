#!/usr/bin/env bash
set -euo pipefail

git fetch --depth 1 origin devcontainer-linux
git checkout --detach FETCH_HEAD

echo "Bootstrapping devcontainer..."

if [ ! -f ~/.bashrc ]; then
  cp ./bashrc ~/.bashrc
fi
if [ ! -f ~/.bash_profile ]; then
  cp ./bash_profile ~/.bash_profile
fi
if [ ! -f ~/.inputrc ]; then
  cp ./inputrc ~/.inputrc
fi
if [ ! -f ~/.profile ]; then
  cp ./profile ~/.profile
fi
if [ ! -f ~/.zshrc ]; then
  cp ./zshrc ~/.zshrc
fi
if [ ! -f ~/.zprofile ]; then
  cp ./zprofile ~/.zprofile
fi
if [ ! -f ~/.zlogin ]; then
  cp ./zlogin ~/.zlogin
fi
if [ ! -f ~/.zlogout ]; then
  cp ./zlogout ~/.zlogout
fi 
