#!/usr/bin/env bash

#######################################################
# Source shared shell configuration
#######################################################
[[ -f ${HOME}/.shellrc ]] && source ${HOME}/.shellrc

#######################################################
# Bash history settings
#######################################################
# Unlimited history
HISTSIZE=-1
HISTFILESIZE=-1
# Append to history file, don't overwrite it
shopt -s histappend
# Ensures output formatting adjusts correctly
shopt -s checkwinsize
# Record timestamps for each command
HISTTIMEFORMAT="%F %T "
# Avoid duplicates and commands starting with space
HISTCONTROL=ignoreboth
# Store history immediately (not just on shell exit)
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"

#######################################################
# Bash prompt configuration
#######################################################
[[ -z ${RED+x} ]] && readonly RED='\[\033[01;31m\]'
[[ -z ${GREEN+x} ]] && readonly GREEN='\[\033[01;32m\]'
[[ -z ${BLUE+x} ]] && readonly BLUE='\[\033[01;34m\]'
[[ -z ${RESET+x} ]] && readonly RESET='\[\033[00m\]'
USER_COLOR=$([[ ${EUID} == 0 ]] && echo "$RED" || echo "$GREEN")
PS1="\n\$(parse_git_info)\n${BLUE}\w\n${USER_COLOR}\u@\h${RESET}:\$ "
