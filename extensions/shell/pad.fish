# pad shell integration for fish
# source this in your config.fish:
#   source ~/git/pad/extensions/shell/pad.fish

set -q PAD_CORE; or set -gx PAD_CORE "$HOME/git/pad/core"

function pad --description "Capture and query with pad"
    set -lx PAD_CWD $PWD
    cd $PAD_CORE; and luajit pad.lua $argv
    cd $PAD_CWD
end

# aliases for common flags
function pad-recent --description "Show recent captures"
    pad --recent
end

function pad-search --description "Search objects"
    pad --search $argv[1]
end

function pad-note --description "Quick note"
    pad --note $argv[1]
end

function pad-stats --description "Show statistics"
    pad --stats
end

function pad-history --description "Show capture history"
    pad --history
end

function pad-recall --description "Search past commands"
    pad --recall $argv[1]
end

function pad-show --description "Show object by ID"
    pad --show $argv[1]
end

function pad-vacuum --description "Age cold objects"
    pad --vacuum
end

function pad-clip --description "Capture clipboard"
    pad --clip
end

function pad-urgent --description "Show urgent/unreviewed items"
    pad --urgent
end

# preexec hook - auto-capture commands
# uncomment to enable: set -g PAD_PREEXEC 1
function __pad_preexec --on-event fish_preexec
    if set -q PAD_PREEXEC
        echo $argv[1] | pad 2>/dev/null &
        disown
    end
end

# completions
complete -c pad -f
complete -c pad -l search -d "Search objects" -r
complete -c pad -l show -d "Show object by ID" -r
complete -c pad -l recent -d "Show recent captures"
complete -c pad -l history -d "Show capture history"
complete -c pad -l sources -d "Show capture sources"
complete -c pad -l note -d "Quick note" -r
complete -c pad -l tag -d "Tag an object" -r
complete -c pad -l untag -d "Remove tag" -r
complete -c pad -l tagged -d "Show objects with tag" -r
complete -c pad -l recall -d "Search past commands" -r
complete -c pad -l orphans -d "Show orphan objects"
complete -c pad -l stats -d "Show statistics"
complete -c pad -l vacuum -d "Age cold objects"
complete -c pad -l gc -d "Garbage collection"
complete -c pad -l urgent -d "Show urgent items"
complete -c pad -l clip -d "Capture clipboard"
complete -c pad -l git-log -d "Capture git log"
complete -c pad -l git-diff -d "Capture git diff"
complete -c pad -l git-status -d "Capture git status"
complete -c pad -l watch -d "Watch file for changes" -r
complete -c pad -l unwatch -d "Stop watching file" -r
complete -c pad -l watching -d "List watched files"
complete -c pad -l daemon -d "Daemon control"
