# global definitions of 7 series command registers
# IR length of the device is 6 bits

# this is best done as a global array
array set 7series_jtag_instr { 	  IDCODE        0x09 \
				      BYPASS        0x3F \
				      EXTEST        0x26 \
				      SAMPLEPRELOAD 0x01 \
				      USERCODE      0x08 \
				      HIGHZ_IO      0x0A \
				      EXTEST_PULSE  0x3C \
				      EXTEST_TRAIN  0x3D \
				      ISC_ENABLE    0x10 \
				      ISC_PROGRAM   0x11 \
				      XSC_PROGRAM_KEY  0x12 \
				      XSC_DNA       0x17 \
				      FUSE_DNA      0x32 \
				      ISC_NOOP      0x14 \
				      ISC_DISABLE   0x16 \
				      CFG_IN        0x05 \
				      CFG_OUT       0x04 \
				      JPROGRAM      0x0B \
				      JSTART        0x0C \
				      JSHUTDOWN     0x0D \
				      USER1         0x02 \
				      USER2         0x03 \
				      USER3         0x22 \
				      USER4         0x23 \
				      XADC_DRP      0x37 }


set 7series_jtag_words_per_frame 101
set 7series_jtag_dummy_frame 1
set 7series_jtag_pipeline_words 0

proc 7series_jtag_get_instrs { } {
    global 7series_jtag_instr
    
    foreach inst [array names 7series_jtag_instr] {
	puts $inst
    }
}

proc 7series_jtag_scan_ir { instr } {
    global 7series_jtag_instr

    if {[expr {[array names 7series_jtag_instr -exact $instr] == {}}]} {
	puts "instruction $instr does not exist"
	return
    }

    # fetch the IR
    set myInstr $7series_jtag_instr($instr)
    # scan the instruction in
    scan_ir_hw_jtag 6 -tdi $myInstr    
}

# there are no other devices in the chain so no bypass option
proc 7series_jtag_scan_dr args {
    array set options {-tdi 0 -len 32}
    array set options $args
    
    set myLength [expr $options(-len)]
    set myTdiInt [expr $options(-tdi)]
    set myTdiDigs [expr $myLength/4 + [expr ($myLength % 4) != 0]]
    set myTdiFormat %0${myTdiDigs}x
    set myTdi [format $myTdiFormat $myTdiInt]
    
    set res [scan_dr_hw_jtag $myLength -tdi $myTdi]
    set myRes [expr 0x$res]
    # get number of hex digits
    set hexDigs [expr $options(-len)/4 + [expr ($options(-len) % 4) != 0]]
    set myFormat %0${hexDigs}x
    # convert to hex because of course
    set myHex 0x[format $myFormat $myRes]
    # the leading 0x lets expr detect it as hex
    return $myHex
}

proc 7series_jtag_read_user4 { len } {
    # my user4 stuff requires an RTI jump to
    # update, so we can add USER4 to the instruction,
    # scan it out, ending in DRPAUSE and jumping
    # back through scan_ir into BYPASS to avoid updating it
    7series_jtag_scan_ir USER4
    run_state_hw_jtag DRPAUSE
    set ret [7series_jtag_scan_dr -tdi 0 -len $len]
    7series_jtag_scan_ir BYPASS
    puts $ret
    return $ret
}

proc 7series_jtag_write_user4 { val len } {
    set myVal [revdec $val $len]
    puts $myVal
    7series_jtag_scan_ir USER4
    set ret [7series_jtag_scan_dr -tdi $myVal -len $len]
    # my user4 stuff requires an RTI run
    # it'll update the first one, but whatever
    runtest_hw_jtag -wait_state IDLE -end_state IDLE -tck 2
    puts $ret
    return $ret
}

# convenience function.
# when we shift crap into the CFG_IN instruction
# they need to be sent MSB first, not LSB first.
proc revdec { val len } {
    # handle dec, bin, hex
    set myVal [expr $val]
    binary scan [binary format "I" $myVal] "B*" binval
    set last [expr $len - 1]
    set myStr [string range $binval end-$last end]
    set myBin [string reverse $myStr]
    return [format "%i" 0b$myBin]
}

proc 7series_jtag_scan_cfg_in { val } {
    set myVal [revdec $val 32]
    # and convert it to hex thanks to stupidity...
    
    7series_jtag_scan_dr -tdi $myVal
}

proc 7series_jtag_scan_cfg_out { args } {
    set myRawVal [7series_jtag_scan_dr]
    # this returns a hex string, so revdec can handle it
    set myVal [revdec $myRawVal 32]
    # and return a hex string of our own for fun
    set myHex 0x[format "%08x" $myVal]
}

# so for instance
# 7series_jtag_scan_ir CFG_IN
# run_state_hw_jtag DRPAUSE
# 7series_jtag_scan_cfg_in 0xAA995566
# 7series_jtag_scan_cfg_in 0x20000000
# 7series_jtag_scan_cfg_in 0x2800E001
# 7series_jtag_scan_cfg_in 0x20000000
# 7series_jtag_scan_cfg_in 0x20000000
# 7series_jtag_scan_ir CFG_OUT
# 7series_jtag_scan_cfg_out

# - this is a readback of STAT, as following 
# note that at the last cfg_in, it ends up in DRPAUSE
# and then 7series_jtag_scan_ir takes it over to SELECT-IR
# via the quick path.
# So this is logically identical to Table 6-5

proc 7series_jtag_readback_config { far nframes } {
    global 7series_jtag_words_per_frame
    global 7series_jtag_dummy_frame
    global 7series_jtag_pipeline_words

    set myFar 0x[format "%08x" [expr $far]]
    puts "FAR is going to be $myFar"
    set myNwords [expr $7series_jtag_words_per_frame*($nframes+$7series_jtag_dummy_frame)+$7series_jtag_pipeline_words]

    set myNwordsHeader [expr $myNwords | (1<<27)]
    set myType2Nwords 0x4[format %07x $myNwordsHeader]

    puts "Type2 is going to be $myType2Nwords"
    # this is a copy of the shutdown readback command sequence
    # table 6-5 in UG470
    run_state_hw_jtag RESET
    zynqmp_jtag_scan_ir CFG_IN
    run_state_hw_jtag DRPAUSE
    # reset CRC
    7series_jtag_scan_cfg_in 0xFFFFFFFF
    7series_jtag_scan_cfg_in 0xAA995566
    7series_jtag_scan_cfg_in 0x20000000
    7series_jtag_scan_cfg_in 0x30008001
    7series_jtag_scan_cfg_in 0x00000007
    7series_jtag_scan_cfg_in 0x20000000
    7series_jtag_scan_cfg_in 0x20000000
    # now shutdown
    7series_jtag_scan_ir JSHUTDOWN
    runtest_hw_jtag -tck 12
    7series_jtag_scan_ir CFG_IN
    run_state_hw_jtag DRPAUSE
    7series_jtag_scan_cfg_in 0xFFFFFFFF
    7series_jtag_scan_cfg_in 0xAA995566
    7series_jtag_scan_cfg_in 0x20000000
    7series_jtag_scan_cfg_in 0x30008001
    7series_jtag_scan_cfg_in 0x00000004
    # write to FAR
    7series_jtag_scan_cfg_in 0x30002001
    7series_jtag_scan_cfg_in $myFar
    7series_jtag_scan_cfg_in 0x28006000
    7series_jtag_scan_cfg_in $myType2Nwords
    7series_jtag_scan_cfg_in 0x20000000
    7series_jtag_scan_cfg_in 0x20000000
    7series_jtag_scan_ir CFG_OUT
    run_state_hw_jtag DRPAUSE
    for {set i 0} {$i < $myNwords} { incr i } {
	set res [7series_jtag_scan_cfg_out]
	puts "$i $res"
    }
    run_state_hw_jtag RESET
}
