# PetaLinux JTAG console

Zynq devices have a "JTAG serial port" in the ARM CoreSight unit
called the "DCC". Enabling this under PetaLinux requires two steps:

1. enabling DCC in the device tree
2. enabling CONFIG_HVC_DCC in the kernel config

This will get you /dev/hvc0 in PetaLinux. However, if you do this on a
ZynqMP (with 4 cores), since *each core* has a DCC port, the serial
output will be sprayed between them randomly. This is because the kernel
thread is randomly running on a core. There's a patch to fix this
in newer kernels, although it's got Giant Big Warnings about being
for "debug code" which I don't understand - it prevents you from
hotplugging _all_ CPUs when you do this.

This recipe backports that patch so that the console works sanely.
I'm not actually sure the hotplug disable actually matters - if
it's being done in userspace, you actually only care about avoiding
offlining CPU0, and you can handle that yourself. Or you could
just, y'know, not offline a CPU if you're using the JTAG serial port.

But I haven't tested that part yet.

## Enabling DCC in the device tree

Add

```
&dcc {
     status = "okay";
};
```

to the system-user.dtsi in project-spec/meta-user/recipes-bsp/device-tree/files.

