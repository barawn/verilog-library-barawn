# This can be used as a post-route script to basically
# just... make it work harder.
# Use set_post_route_tcl "try_harder.tcl"

proc timing_ok {} {
    return [expr [get_property SLACK [get_timing_paths -delay_type min_max]] >= 0]
}

if { ! [timing_ok] } {
    puts "Initial attempt at meeting timing failed, trying to fix..."
    place_design -post_place_opt
    route_design -directive Explore
} else {
    puts "Design met timing, no extra effort needed"
}
