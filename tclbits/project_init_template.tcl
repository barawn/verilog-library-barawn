# Returns the base directory of the project. Assumes
# the project is stored in a subdirectory of the repository top level
# e.g. repo is "this_project", and project is in "this_project/vivado_project"
proc get_repo_dir {} {
    set projdir [get_property DIRECTORY [current_project]]
    set projdirlist [ file split $projdir ]
    set basedirlist [ lreplace $projdirlist end end ]
    return [ file join {*}$basedirlist ]
}

# You might want to grab the utility.tcl file:
# source [file join [get_repo_dir] verilog-library-barawn tclbits utility.tcl]
#
# You also might want to grab the repo_files.tcl file:
# source [file join [get_repo_dir] verilog-library-barawn tclbits repo_files.tcl]
# And then if you do that, you might want to check all files every time
# you open the project
#
# check_all
#
# And similarly you might want to create a "project_deinit.tcl", based
# on "project_deinit_template.tcl"
