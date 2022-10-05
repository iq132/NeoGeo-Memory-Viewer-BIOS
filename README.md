# NeoGeo Memory Viewer BIOS

A drop-in replacement for the NeoGeo bios that allows the user to view and write to any address in the NeoGeo`s memory space. This bios ***WILL NOT BOOT GAMES*** and is not designed to.

# Use
To use this on your hardware, you will have to build a binary (see Building).
You will then have to burn to a 27c1024 (or compatible) EPROM and install it into your NeoGeo`s 68K bios socket.
The controls are : P1 Start selects what you are going to change, The P1 up/down buttons change the lowest digit, left/right, the next, a/b, the next, c/d the next.
if you select [Poke], any P1 button (UDLRABCD) should write the value.

# Developer
IQ_132 -  http://neo-source.com

# Credits
https://wiki.neogeodev.org for a variety of useful information.

# Building

Use Easy68k (http://www.easy68k.com) to edit and assemble a binary.
Before use, the binary must be byteswapped (byte 0->1, byte 1<-0).

# Legalese
Use at your own risk, there is no promise that this cannot damage your hardware. It has been tested on an MV1F and MV1FS and works fine on both.
Additionally, I do not care how this source is used as long as that with the release of any binaries, source changes are also published.
