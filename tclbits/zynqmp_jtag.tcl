# global definitions of Zynq Ultrascale+ command registers.
# Keep in mind that the combined IR for the device is 16
# bits long, because it includes the SoC TAP + ARM DAP.
# The SoC TAP is 12 bits, the ARM DAP is 4 bits (regardless
# of what you read in the TRM, this is true).

# The DAP comes AFTER the TAP, and JTAG shifts in LSB first.
# So you need to put the DAP in BYPASS for everything:
# this means appending 'F' after all of these commands.
# Hence the append var 'F' later.

# Dealing with the DAP is a lot of what's going on here:
# if you don't understand, in a JTAG chain, if a device
# is in bypass, it still affects things by adding a
# single bit shift register between TDI->TDO.
# Because the DAP is *after* the TAP and JTAG is shifted in
# LSB first, this means when we shift in, we need to upshift
# everything by 1 and clock in an additional bit, and
# when we shift out, we need to clock an additional bit and
# downshift the results by 1.

# However, if you're doing a MULTIPLE shift (by hopping
# through DRPAUSE each time) you only need to do this *one time*.

# Note that for a pure shift in (don't care about the output)
# you can skip the upshift by 1.

# NOTE: you could adapt this whole thing for non-Zynq devices
# by 1) changing the instruction array and 2) getting rid of the
# additional F append in the IR shift and 3) adjusting things
# to ensure that -bypass is always zero in the DR shift.

# The PS TAP is *implemented* as two separate 6-bit
# JTAG like objects, but they're not IEEE JTAG compliant:
# you don't get 2 IDCODEs in RESET, you don't get an extra
# bit if you put one in bypass, etc.
# And the BSDL for the SoC just lists everything as 12-bit
# objects.
# I think basically the top 6-bits being 10_0100 bypasses the PS
# TAP and you get only the PL tap or something. I dunno. It's weird.

# this is best done as a global array
array set zynqmp_jtag_instr { \
				  IDCODE        0x249 \
				  IDCODE_PL     0x925 \
				  IDCODE_PSPL   0x265 \
				  BYPASS        0xFFF \
				  EXTEST        0x9A6 \
				  SAMPLEPRELOAD 0xFC1 \
				  USERCODE      0x908 \
				  HIGHZ_IO      0x28A \
				  JTAG_STATUS   0x7FF \
				  JSTATUS       0x921 \
				  EXTEST_PULSE  0x9BC \
				  EXTEST_TRAIN  0x9BD \
				  ISC_ENABLE    0x910 \
				  ISC_PROGRAM   0x911 \
				  ISC_PROG_SEC  0x912 \
				  ISC_NOOP      0x914 \
				  ISC_DISABLE   0x916 \
				  ISC_READ      0x915 \
				  XSC_DNA       0x917 \
				  CFG_IN        0x905 \
				  CFG_OUT       0x904 \
				  JPROGRAM      0x90B \
				  JSTART        0x90C \
				  JSHUTDOWN     0x90D \
				  FUSE_CTS      0x930 \
				  FUSE_KEY      0x931 \
				  FUSE_DNA      0x932 \
				  FUSE_CNTL     0x934 \
				  FUSE_USER_PS  0x23F \
				  USER1         0x902 \
				  USER2         0x903 \
				  USER3         0x922 \
				  USER4         0x923 \
				  SYSMON_DRP    0x937 \
				  JTAG_CTRL     0x83F \
				  ERROR_STATUS  0xFBF \
				  PMU_MDM       0x0FF }

proc zynqmp_jtag_get_instrs { } {
    global zynqmp_jtag_instr
    
    foreach inst [array names zynqmp_jtag_instr] {
	puts $inst
    }
}

proc zynqmp_jtag_scan_ir { instr } {
    global zynqmp_jtag_instr

    if {[expr {[array names zynqmp_jtag_instr -exact $instr] == {}}]} {
	puts "instruction $instr does not exist"
	return
    }

    # fetch the IR
    set myInstr $zynqmp_jtag_instr($instr)
    # put the DAP in bypass
    append myInstr F
    # scan the instruction in
    scan_ir_hw_jtag 16 -tdi $myInstr    
}

# Scan DR, optionally accounting for the DAP bypass bit.
# A pure "in" scan doesn't need to (the DAP is after the TAP)
# A single 'out' scan needs to.
# A multiple 'out' scan needs to do it once: the DAP stays in bypass,
# so it continues to hold a bit.
proc zynqmp_jtag_scan_dr args {
    array set options {-tdi 0 -len 32 -bypass 1}
    array set options $args
    
    # add 1 for the DAP bypass reg
    set myLength [expr $options(-len) + $options(-bypass)]
    # and upshift tdi. Note that this is silly if it's 0, but whatever.
    set myTdiInt [expr $options(-tdi) << $options(-bypass)]
    set myTdiDigs [expr $myLength/4 + [expr ($myLength % 4) != 0]]
    set myTdiFormat %0${myTdiDigs}x
    set myTdi [format $myTdiFormat $myTdiInt]
    
    set res [scan_dr_hw_jtag $myLength -tdi $myTdi]
    set myRes [expr 0x$res >> $options(-bypass)]
    # get number of hex digits
    set hexDigs [expr $options(-len)/4 + [expr ($options(-len) % 4) != 0]]
    set myFormat %0${hexDigs}x
    # convert to hex because of course
    set myHex 0x[format $myFormat $myRes]
    # the leading 0x lets expr detect it as hex
    return $myHex
}

# convenience function.
# when we shift crap into the CFG_IN instruction
# they need to be sent MSB first, not LSB first.
proc revdec { val len } {
    # handle dec, bin, hex
    set myVal [expr $val]
    binary scan [binary format "I" $val] "B*" binval
    set myStr [string range $binval end-$len end]
    set myBin [string reverse $myStr]
    return [format "%i" 0b$myBin]
}

proc zynqmp_jtag_scan_cfg_in { val args } {
    array set options { -first 0 }
    array set options $args
    set myBypass $options(-first)
    set myVal [revdec $val 32]
    # and convert it to hex thanks to stupidity...
    
    zynqmp_jtag_scan_dr -tdi $myVal -bypass $myBypass
}

proc zynqmp_jtag_scan_cfg_out { args } {
    array set options { -first 0 }
    array set options $args
    set myBypass $options(-first)
    set myRawVal [zynqmp_jtag_scan_dr -bypass $myBypass]
    # this returns a hex string, so revdec can handle it
    set myVal [revdec $myRawVal 32]
    # and return a hex string of our own for fun
    set myHex 0x[format "%08x" $myVal]
}

# so for instance
# zynqmp_jtag_scan_ir CFG_IN
# run_state_hw_jtag DRPAUSE
# zynqmp_jtag_scan_cfg_in 0xAA995566 -first 1
# zynqmp_jtag_scan_cfg_in 0x20000000
# zynqmp_jtag_scan_cfg_in 0x2800E001
# zynqmp_jtag_scan_cfg_in 0x20000000
# zynqmp_jtag_scan_cfg_in 0x20000000
# zynqmp_jtag_scan_ir CFG_OUT
# zynqmp_jtag_scan_cfg_out -first 1

# - this is a readback of STAT, as following 
# note that at the last cfg_in, it ends up in DRPAUSE
# and then zynqmp_jtag_scan_ir takes it over to SELECT-IR
# via the quick path.
# So this is logically identical to Table 10-5
