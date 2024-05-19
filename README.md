CannonBall - OutRun Engine
==========================

This is an experimental port of CannonBall, an open source game engine for the OutRun arcade game. This fork focuses on Apple platforms, making use of whatever special doohickeys that exist. At least that's the goal, anyways. **Do not expect anything good, I don't know what I'm doing.**

For an overview of CannonBall and its features, please read the original [manual](https://github.com/djyt/cannonball/wiki).

CannonBall is written by Chris White ([Blog](http://reassembler.blogspot.co.uk/), [Twitter](https://twitter.com/djyt)). 


Getting Started
---------------

CannonBall is coded in C++ and makes use of the SDL 2 and Boost libraries. 
**Do not use this fork to port to other platforms.** Please use the original repository instead. 

* Install your favourite C++ environment.
* Install [CMake](http://www.cmake.org/). Verify that CPack is also installed with it.
* Install the [Boost Library](http://www.boost.org/) with Homebrew, or any other method.
* Install the [SDL Development Library](https://www.libsdl.org/download-2.0.php) with Homebrew, or any other method.
* Extract the CannonBall code somewhere.
* Check the macos.cmake file, and make modifications if necessary.

Build
-----

* Run CMake to generate the relevant build files for your compiler. You can optionally pass -DTARGET=filename to pass a custom .cmake file.
* Compile
* Run CPack to create a full, usable .dmg file.