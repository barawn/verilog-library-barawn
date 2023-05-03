# Tcl snippets for Vivado

These bits of Tcl code assume you've installed a Vivado_init.tcl script
as in the top directory. This provides for opening a project_init.tcl
script that is located in the project top directory.

Some of these functions may seem like they duplicate GUI functions
(like add_include_dir). You use these instead of GUI functions to
ensure that the project state stays consistent between users without
trying to check in/recreate the project file every time. There are
"guards" inside the functions to prevent adding the same function
multiple times.

**Note**: To use these you must have the "get_repo_dir" proc. This
is provided in the default project_init.tcl below assuming you
have a Vivado_init.tcl which provides for per-project initialization.

* project_init_template.tcl - Basic project initialization file. Copy this to
  project_init.tcl in your project's repository directory.

* utility.tcl - This file contains a bunch of utility procedures to simplify
  Tcl scripts, including adding scripts/include directories to the projects.

* try_harder.tcl - This file can be used as a post-route Tcl script to,
  well... just try harder. If Vivado's route attempt fails, sometimes
  the key is to just rerun the placer with the post-place optimization
  (which now has route information), and it'll try to replace the failing
  elements (and then route, obviously).

