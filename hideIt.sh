#!/bin/bash
#
#   Automagically hide/show a window by its name when the cursor is
#   within a defined region or you mouse over it.
#
#   This script was initially written to imitate gnome-shell's systray
#   but should be generic enough to do other things as well.
#
#   Requirements:
#      bash, xdotool, xwininfo
#

# Global variables used throughout the script
win_id=""
win_name=""

win_width=""
win_height=""
win_posX=""
win_posY=""

screen_width=""
screen_height=""

minX=""
minY=""
maxX=""
maxY=""

hover=1
interval=1
peek=3
direction="left"
steps=1
no_trans=1

_is_hidden=1
_has_region=1


usage() {
    # Print usage
    printf "usage: $0 [options]\n"
    printf "\n"
    printf "Required:\n"
    printf " -N, --name [window-name]\n"
    printf "   The name of the window to hide.\n"
    printf "\n"
    printf "Optional:\n"
    printf " -r, --region [posXxposY+offsetX+offsetY]\n"
    printf "   Cursor region at which to trigger.\n"
    printf "   Examples:\n"
    printf "     --region 0x1080+10+-10 (Bottom left incl. a 10 pixel offset)\n"
    printf "     --region 1920x1080+0+0 (Bottom right without offset)\n"
    printf "\n"
    printf " -H, --hover\n"
    printf "   Show the window when hovering over it.\n"
    printf "   If a region was defined, hover will be ignored!\n"
    printf "   This will only work if --peek is greater 0.\n"
    printf "   By default, hover is off.\n"
    printf "\n"
    printf " -i, --interval [interval]\n"
    printf "   Interval in seconds to check the cursors location.\n"
    printf "   Defaults to 1.\n"
    printf "\n"
    printf " -p, --peek [amount]\n"
    printf "   When moved out, peek 'amount' of pixels to indicate the window.\n"
    printf "   Defaults to 3.\n"
    printf "\n"
    printf " -d, --direction [left|right|top|bottom]\n"
    printf "   Direction in which to move the window.\n"
    printf "   Defaults to left.\n"
    printf "\n"
    printf " -s, --steps [amount]\n"
    printf "   Steps in pixel used to move the window. The higher the value,\n"
    printf "   the faster it will move at the cost of smoothness.\n"
    printf "   Defaults to 1.\n"
    printf "\n"
    printf " -T, --no-trans\n"
    printf "   Turn of the transition effect.\n"
}


argparse() {
    # Parse system args
    while [ $# -gt 0 ]; do
        case $1 in
            "-N"|"--name")
                win_name="$2"
                shift
                ;;
            "-H"|"--hover")
                hover=0
                ;;
            "-r"|"--region")
                local posX posY offsetX offsetY
                read posX posY offsetX offsetY <<<$(echo "$2" | \
                    sed -rn 's/^([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+)/\1 \2 \3 \4/p')

                # Test if we have proper values by trying
                # to add them all together
                expr $posX + $posY + $offsetX + $offsetY > /dev/null 2>&1
                if [ $? -ne 0 ]; then
                    printf "Invalid region. See --region for help.\n" 1>&2
                    exit 1
                fi

                minX=$posX
                maxX=$((${minX} + ${offsetX}))
                if [ $minX -gt $maxX ]; then
                    read minX maxX <<< "$maxX $minX"
                fi

                minY=$posY
                maxY=$((${minY} + ${offsetY}))
                if [ $minY -gt $maxY ]; then
                    read minY maxY <<< "$maxY $minY"
                fi

                if [[ ! $minX =~ [0-9]+ ]] || [[ ! $minY =~ [0-9]+ ]] \
                        || [[ ! $maxY =~ [0-9]+ ]] || [[ ! $maxY =~ [0-9]+ ]]; then
                    printf "Missing or invalid region. See --region for help.\n" 1>&2
                    exit 1
                fi
                _has_region=0
                shift
                ;;
            "-i"|"--interval")
                interval="$2"
                if [[ ! $interval =~ [0-9]+ ]]; then
                    printf "Interval should be a number. " 1>&2
                    exit 1
                fi
                shift
                ;;
            "-p"|"--peek")
                peek="$2"
                if [[ ! $peek =~ [0-9]+ ]]; then
                    printf "Peek should be a number. " 1>&2
                    exit 1
                fi
                shift
                ;;
            "-d"|"--direction")
                direction="$2"
                if [[ ! "$direction" =~ ^(left|right|top|bottom)$ ]]; then
                    printf "Invalid direction. " 1>&2
                    printf "Should be one of left, right, top, bottom.\n" 1>&2
                    exit 1
                fi
                shift
                ;;
            "-s"|"--steps")
                steps="$2"
                if [[ ! $steps =~ [0-9]+ ]]; then
                    printf "Steps should be a number. " 1>&2
                    exit 1
                fi
                shift
                ;;
            "-T"|"--no-trans")
                no_trans=0
                ;;
            "-h"|"--help")
                usage
                exit 0
                ;;
            **)
                printf "Didn't understand '$1'\n" 1>&2
                printf "Use -h, --help for usage information.\n"
                exit 1
                ;;
        esac
        shift
    done

    # Check required arg
    if [ -z "$win_name" ]; then
        printf "Window name required. See --name for help.\n" 1>&2
        exit 1
    fi
}


function fetch_window_id() {
    # Sets the values for the following global
    #   win_id
    win_id="$(xdotool search --name "$win_name")"
}


function fetch_screen_dimensions() {
    # Sets the values for the following globals
    #    screen_width, screen_height

    local win_info=$(xwininfo -root)
    screen_width=$(echo "$win_info" | sed -rn 's/.*Width: +([0-9]+)/\1/p')
    screen_height=$(echo "$win_info" | sed -rn 's/.*Height: +([0-9]+)/\1/p')
}


function fetch_window_dimensions() {
    # Sets the values for the following globals unless no win_id exists
    #    win_width, win_height, win_posX, win_posY
    if [[ ! $win_id =~ [0-9]+ ]]; then
        return
    fi

    local win_info=$(xwininfo -id $win_id)

    win_width=$(echo "$win_info" | sed -rn 's/.*Width: +([0-9]+)/\1/p')
    win_height=$(echo "$win_info" | sed -rn 's/.*Height: +([0-9]+)/\1/p')

    if [ ! -z "$1" ] && [ $1 -eq 0 ]; then
        win_posX=$(echo "$win_info" | sed -rn 's/.*Absolute upper-left X: +(-?[0-9]+)/\1/p')
        win_posY=$(echo "$win_info" | sed -rn 's/.*Absolute upper-left Y: +(-?[0-9]+)/\1/p')
    fi
}


function hide_window() {
    # Move the window in or out
    # Args:
    #     hide: 0 to hide, 1 to show
    local hide=$1

    _is_hidden=$hide

    # Update win_width, win_height in case they changed
    fetch_window_dimensions

    if [ $hide -eq 1 ]; then
        xdotool windowactivate $win_id > /dev/null 2>&1
    fi

    local sequence=""
    if [ "$direction" == "left" ]; then
        if [ $hide -eq 0 ]; then
            sequence=($(seq $win_posX -$steps -$(($win_width - $peek))))
        else
            sequence=($(seq -$(($win_width - $peek)) $steps $win_posX))
        fi

    elif [ "$direction" == "right" ]; then
        if [ $hide -eq 0 ]; then
            sequence=($(seq $win_posX $steps $(($screen_width - $peek))))
        else
            sequence=($(seq $(($screen_width - $peek)) -$steps $win_posX))
        fi

    elif [ "$direction" == "bottom" ]; then
        if [ $hide -eq 0 ]; then
            sequence=($(seq $win_posY $steps $(($screen_height - $peek))))
        else
            sequence=($(seq $(($screen_height - $peek)) -$steps $win_posY))
        fi

    elif [ "$direction" == "top" ]; then
        if [ $hide -eq 0 ]; then
            sequence=($(seq $win_posY -$steps -$(($win_height - $peek))))
        else
            sequence=($(seq -$(($win_height - $peek)) $steps $win_posY))
        fi
    fi

    if [ $no_trans -eq 1 ]; then
        for i in ${sequence[@]}; do
            if [[ "$direction" =~ ^(left|right)$ ]]; then
                xdotool windowmove $win_id $i y
            elif [[ "$direction" =~ ^(top|bottom)$ ]]; then
                xdotool windowmove $win_id x $i
            fi
        done
    else
        pos=${sequence[-1]}
        if [[ "$direction" =~ ^(left|right)$ ]]; then
            xdotool windowmove $win_id $pos y
        elif [[ "$direction" =~ ^(top|bottom)$ ]]; then
            xdotool windowmove $win_id x $pos
        fi
    fi
}


function serve() {
    # Check if the cursors location and act accordingly
    local _hide=0

    while true; do
        eval $(xdotool getmouselocation --shell)


        # Test if the cursor is within the region
        if [ $_has_region -eq 0 ]; then
            if [ $X -ge $minX -a $X -le $maxX ] \
                    && [ $Y -ge $minY -a $Y -le $maxY ]; then
                _hide=1
            else
                _hide=0
            fi

        elif [ $hover -eq 0 ]; then
            if [ $WINDOW -eq $win_id ]; then
                _hide=1
            else
                _hide=0
            fi
        fi

        if [ $_is_hidden -ne 0 ] \
                && [ $_hide -eq 0 ] \
                && [ $WINDOW -eq $win_id ]; then
            _hide=1
        fi

        # Only do something if necessary
        if [ $_is_hidden -ne $_hide ]; then
            hide_window $_hide
        fi

        sleep $interval
    done
}


function restore() {
    hide_window 1
}


function main() {
    argparse "$@"

    printf "Searching window...\n"
    fetch_window_id
    if [[ ! $win_id =~ [0-9]+ ]]; then
        printf "No window found!\n" 1>&2
        exit 1
    else
        printf "Found window with id: $win_id\n"
    fi

    printf "Fetching window dimensions...\n"
    fetch_window_dimensions 0

    printf "Fetching screen dimensions...\n"
    fetch_screen_dimensions

    printf "Initially hiding window...\n"
    trap restore EXIT
    hide_window 0


    printf "Defined region:\n"
    printf "  X: $minX $maxX\n"
    printf "  Y: $minY $maxY\n"
    printf "\n"

    printf "Waiting for trigger..."
    serve

    exit 0
}

# Lets do disss!
main "$@"