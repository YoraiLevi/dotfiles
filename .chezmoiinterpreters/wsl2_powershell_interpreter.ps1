param()
wsl bash --noprofile --norc "$(wsl wslpath $args.replace('\','/'))"