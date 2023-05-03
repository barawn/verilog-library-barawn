# Procedure for dumping sources in a project.
# fs_name is fileset name, filename is file to write to,
# and the last (optional) argument is the filter type.
# This lets you kill generated files, for instance.
# e.g. dump_files "sources_1" "sources.txt" "IS_GENERATED==0"
proc dump_files { fs_name filename args } {
    # Get the length of the project repository path
    set repodir_length [ expr [string length [get_repo_dir]] + 1]
    # get file list
    if {[llength $args] == 0} {
	set fs [get_files -of_objects [get_fileset $fs_name]]
    } else {
	set fs [get_files -of_objects [get_fileset $fs_name] -filter [lindex $args 0]]
    }
    # create filename in repo
    set fn [file join [get_repo_dir] $filename]
    # open file
    set fp [open $fn w]
    foreach f $fs {
	puts $fp [ string range $f $repodir_length end ]
    }
    close $fp
}

# Procedure for dumping IP files in a project.
proc dump_ip_files { impl_filename sim_filename } {
    # This takes so much effort because we need to extract whether or not it's only used
    # in simulation or not.
    set repodir_length [ expr [string length [get_repo_dir]] + 1]
    
    # First build up a list of IPs filenames
    set ipfs [list]
    foreach ip [get_ips -exclude_bd_ips] { lappend ipfs [get_property IP_FILE $ip] }
    # Now open both files
    set iip [open [file join [get_repo_dir] $impl_filename] w]
    set sip [open [file join [get_repo_dir] $sim_filename] w]
    foreach ipf $ipfs {
	if {[get_property USED_IN_IMPLEMENTATION [get_files $ipf]]} {
	    puts $iip [ string range $ipf $repodir_length end ]
	} else {
	    puts $sip [ string range $ipf $repodir_length end ]
	}
    }
    close $iip
    close $sip
}

proc save_all {} {
    dump_files "sources_1" "sources.txt" "IS_GENERATED==0"
    dump_files "constrs_1" "constraints.txt"
    dump_files "sim_1" "simulation.txt"
    dump_ip_files "ips.txt" "simips.txt"
}

# Read in the file list and restore it if missing
# Note that Xilinx says you should not use add_files
# for IPs/block designs...
# ... apparently they've never actually, y'know,
# *tried*. It works fine.
proc check_all {} {
    # check sources...
    set sf [open [file join [get_repo_dir] "sources.txt"] r]
    while {[gets $sf line]>=0} {
	set fn [file join [get_repo_dir] $line]
	if { ! [llength [get_files $fn]] } {
	    puts "Adding missing source file $fn"
	    add_files -norecurse -fileset [get_filesets sources_1] $fn
	}
    }
    close $sf
    # check constraints...
    set cf [open [file join [get_repo_dir] "constraints.txt"] r]
    while {[gets $cf line] >=0} {
	set fn [file join [get_repo_dir] $line]
	if { ! [llength [get_files $fn]] } {
	    puts "Adding missing constraint file $fn"
	    add_files -norecurse -fileset [get_filesets constrs_1] $fn
	}
    }
    close $cf
    # check simulation files...
    set mf [open [file join [get_repo_dir] "simulation.txt"] r]
    while {[gets $mf line] >= 0} {
	set fn [file join [get_repo_dir] $line]
	if { ! [llength [get_files $fn]] } {
	    puts "Adding missing sim file $fn"
	    add_files -norecurse -fileset [get_filesets sim_1] $fn
	}
    }
    close $mf
    # check main IP files...
    set ipf [open [file join [get_repo_dir] "ips.txt"] r]
    while {[gets $ipf line] >= 0} {
	set fn [file join [get_repo_dir] $line]
	if { ! [llength [get_files $fn]]} {
	    puts "Adding missing IP file $fn"
	    add_files -norecurse -fileset [get_filesets sources_1] $fn
	}
    }
    # and finally check sim IP files
    set sif [open [file join [get_repo_dir] "simips.txt"] r]
    while {[gets $sif line] >= 0} {
	set fn [file join [get_repo_dir] $line]
	if { ! [llength [get_files $fn]]} {
	    puts "Adding missing IP file $fn"
	    add_files -norecurse -fileset [get_filesets sim_1] $fn
	}
    }
}
