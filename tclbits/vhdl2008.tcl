# Sigh. VHDL/VHDL 2008 are incompatible in Vivado, so we need
# to track whether a file should be added as VHDL or VHDL 2008.
# Easiest way to do that is to just generate a file with all the VHDL 2008
# files and we'll check that they're set properly each time we load.

# Get all files in a fileset that are VHDL-2008. For convenience.
proc get_vhdl2008 { fs } {
    set l [list]
    foreach f [get_files -of_objects $fs] {
	if {[get_property FILE_TYPE $f]=="VHDL 2008"} {
	    lappend l $f
	}
    }
    return $l
}

# Find all files in a fileset that have type VHDL-2008 and write to filename.
proc save_vhdl2008 { fs filename } {
    # Get length of the project repository path so it can be trimmed off
    set repodir_length [ expr [string length [get_repo_dir]] + 1]
    set l [get_vhdl2008 $fs]
    set fn [file join [get_repo_dir] $filename]
    set fp [open $fn w]
    foreach f $l {
	puts $fp [ string range $f $repodir_length end]
    }
    close $fp
}

# Check all files listed in a filename to see if they're VHDL2008
proc check_vhdl2008 { filename } {
    set sf [open [file join [get_repo_dir] $filename ] r]
    while {[gets $sf line]>=0} {
	set fn [file join [get_repo_dir] $line]
	set f [get_files $fn]
	if { ! [llength $f] } {
	    puts "VHDL file $fn is not in repository!"
	    close $sf
	    return
	}
	if {[get_property FILE_TYPE $f]!="VHDL 2008"} {
	    puts "Updating VHDL file $fn type to VHDL-2008"
	    set_property FILE_TYPE "VHDL 2008" $f
	}
    }
    close $sf
}
