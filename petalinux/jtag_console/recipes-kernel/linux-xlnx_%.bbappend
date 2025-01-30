FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}"

SRC_URI += "file://0001-backport-DCC-uart-serialization-option.patch \
	    file://0002-enable-DCC-and-serialize.cfg \
	    "
