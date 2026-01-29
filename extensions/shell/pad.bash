# pad shell integration
# source this in your .bashrc/.zshrc

PAD_CORE="${PAD_CORE:-$HOME/git/pad/core}"

pad() {
  (PAD_CWD="$PWD" cd "$PAD_CORE" && luajit pad.lua "$@")
}

# aliases for common flags
pad-recent()  { pad --recent; }
pad-search()  { pad --search "$1"; }
pad-note()    { pad --note "$1"; }
pad-stats()   { pad --stats; }
pad-history() { pad --history; }
pad-recall()  { pad --recall "$1"; }
pad-show()    { pad --show "$1"; }
pad-vacuum()  { pad --vacuum; }

# preexec hook for zsh - auto-capture commands
# add to .zshrc: preexec() { pad-preexec "$1"; }
pad-preexec() {
  local cmd="$1"
  # logs the command as an event (does not capture output)
  echo "$cmd" | pad
}
