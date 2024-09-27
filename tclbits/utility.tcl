# Utility procedures

# utility function. Use add_include_dir unless necessary
proc add_include_dir_to_fileset { idir fileset } {
    if {[string equal [file pathtype $idir] "absolute"]} {
	set incdir $idir
    } else {
	set incdir [file join [get_repo_dir] $idir]
    }
    set incdirlist [get_property include_dirs $fileset ]
    if {$incdir in $incdirlist} {
	puts "Skipping directory include, already done"
    } else {
	puts "Adding $idir to include directories"	
	lappend incdirlist $incdir	
	set_property include_dirs $incdirlist $fileset
    }
}

# Procedure to add an include dir.
# Pass a path relative to the base project (repository) directory.
# e.g. do
# add_include_dir "include"
proc add_include_dir { idir } {
    add_include_dir_to_fileset $idir [current_fileset]
    add_include_dir_to_fileset $idir [get_filesets sim_1]
}



# Utility function for setting a script. Shortens
# the convenience functions below.
proc set_script { scr property_name fileset_name run_name } {
    set scrip [ file join [get_repo_dir] $scr ]
    if {$scrip in [get_files -of_objects [get_filesets $fileset_name]]} {
	# skip
    } else {
	add_files -fileset [get_filesets $fileset_name] -norecurse $scrip
	set_property $property_name [ get_files $scrip -of [get_fileset $fileset_name]] [get_runs $run_name]
    }
}

# Procedure to set a pre-synthesis script
# Pass a path relative to the base project (repository) directory.
# e.g. do
# set_pre_synthesis_tcl "pre_synthesis.tcl"
# NOTE: This only works if you don't change the filesets and default
# run types. Which I never ever ever do.
proc set_pre_synthesis_tcl { prescr } {
    set_script $prescr "STEPS.SYNTH_DESIGN.TCL.PRE" "utils_1" "synth_1"
}

# As above, for post-implementation init script
# Post implementation init happens after loading all constraints.
# Pass a path relative to the base project (repository) directory.
# e.g. do
# set_post_implementation_init_tcl "post_implementation_init.tcl"
# NOTE: This only works if you don't change the filesets and default
# run types. Which I never ever ever do.
proc set_post_implementation_init_tcl { pinitscr } {
    set_script $pinitscr "STEPS.INIT_DESIGN.TCL.POST" "utils_1" "impl_1"
}

# As above, for post-place script
proc set_post_place_tcl { pplacescr } {
    set_script $pplacescr "STEPS.PLACE_DESIGN.TCL.POST" "utils_1" "impl_1"
}

# As above, for post-route script
proc set_post_route_tcl { proutescr } {
    set_script $proutescr "STEPS.ROUTE_DESIGN.TCL.POST" "utils_1" "impl_1"
}

# As above, for pre-write bistream
proc set_pre_write_bitstream_tcl { pwritescr } {
    set_script $pwritescr "STEPS.WRITE_BITSTREAM.TCL.PRE" "utils_1" "impl_1"
}

# As above, for post-write bitstream
proc set_post_write_bitstream_tcl { ptwritescr } {
    set_script $ptwritescr "STEPS.WRITE_BITSTREAM.TCL.POST" "utils_1" "impl_1"
}

# Utility function for adding IP repository. 
proc add_ip_repository { iprep } {
    if {[string equal [file pathtype $iprep] "absolute"]} {
	set iprepf $iprep
    } else {
	set iprepf [file join [get_repo_dir] $iprep]
    }
    set ipreps [get_property ip_repo_paths [current_project]]
    if {$iprepf in $ipreps} {
	# do nothing
    } else {
	lappend ipreps $iprepf
	set_property ip_repo_paths $ipreps [current_project]
    }
}
