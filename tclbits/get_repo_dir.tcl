# THIS SHOULD BE AT THE BEGINNING OF YOUR project_init.tcl !
# Don't try to source this file, because Tcl might not know where
# this file is!

# Returns the base directory of the project. Assumes
# the project is stored in a subdirectory of the repository top level
# e.g. repo is "this_project", and project is in "this_project/vivado_project"
proc get_repo_dir {} {
    set projdir [get_property DIRECTORY [current_project]]
    set projdirlist [ file split $projdir ]
    set basedirlist [ lreplace $projdirlist end end ]
    return [ file join {*}$basedirlist ]
}

