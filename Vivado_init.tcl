rename open_project open_project_builtin
rename close_project close_project_builtin

proc open_project args {
    open_project_builtin {*}$args
    set projdir [get_property DIRECTORY [current_project]]
    set projdirlist [ file split $projdir ]
    set projdirname [ lindex $projdirlist end ]
    if {[string compare $projdirname "vivado_project"] == 0} {
        # git managed project
        set basedirlist [ lreplace $projdirlist end end ]
        set basedir [ file join {*}$basedirlist ]
        set projinit [ file join $basedir "project_init.tcl"]
    } else {
        set projinit [ file join $projdir "project_init.tcl"]
    }
    if {[file exists $projinit] == 1} {
        source $projinit
    }
}

# Close project is tougher than open
# because we always want to be able to close the project
# even if there's an error thrown. So we bracket the
# whole thing in a catch block.
#
# If the same thing happens in open_project, you'll see it there.
proc close_project args {
    set projdir [get_property DIRECTORY [current_project]]
    set projdirlist [ file split $projdir ]
    set projdirname [ lindex $projdirlist end]
    if {[string compare $projdirname "vivado_project"] == 0} {
	# git managed project
	set basedirlist [ lreplace $projdirlist end end ]
	set basedir [ file join {*}$basedirlist ]
	set projdeinit [ file join $basedir "project_deinit.tcl"]
    } else {
	set projdeinit [ file join $projdir "project_deinit.tcl"]
    }    
    if {[file exists $projdeinit] == 1} {
	set err [catch {source $projdeinit}]
	if { $err } {
	    puts stderr "project_deinit tcl script had error $err" 
	}
    }
    close_project_builtin {*}$args
}

set_param general.maxThreads 16
