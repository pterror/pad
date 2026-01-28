# pad shell integration
# source this in your .bashrc/.zshrc

# core pad command - points to the luajit binary running pad.lua
PAD_CORE="${PAD_CORE:-$HOME/git/pad/core}"
PAD_BIN="$PAD_CORE/dep/luajit"
PAD_LUA="$PAD_CORE/pad.lua"

pad() {
  (cd "$PAD_CORE" && "$PAD_BIN" "$PAD_LUA" "$@")
}

# convenience aliases that pass source metadata
pad-exec() {
  # capture command output and ingest with exec source
  pad "$@"
}

pad-history() {
  # ingest shell history
  history | pad
}

pad-env() {
  # ingest environment
  env | pad
}

# hook for capturing command output
# usage: some_command | pad-capture "description"
pad-capture() {
  local desc="${1:-stdin}"
  pad  # reads from stdin, source=stdin by default
}

# pre-exec hook for zsh (optional - captures all commands)
# add to .zshrc: preexec() { pad-preexec "$1"; }
pad-preexec() {
  local cmd="$1"
  # could log commands here if desired
}
