# Verilog library of modules

"hdl" contains synthesizable modules, "sim" contains behavioral modules.

## Automating project_init.tcl

Vivado automatically runs an "init.tcl" or "Vivado_init.tcl" script when it
launches, but it doesn't have a way to do this on a per-project basis.
But you can **create** a way. Add the following to the init.tcl/Vivado_init.tcl
(whichever you use):

```tcl
rename open_project open_project_builtin

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
```

The location of the init.tcl should follow here:
https://support.xilinx.com/s/article/53090?language=en_US
