CannonBall - OutRun Engine
==========================

This is an experimental port of CannonBall, an open source game engine for the OutRun arcade game. This fork focuses on Apple platforms, making use of whatever special doohickeys that exist. At least that's the goal, anyways. **Do not expect anything good, I don't know what I'm doing.**

For an overview of CannonBall and its features, please read the original [manual](https://github.com/djyt/cannonball/wiki).

CannonBall is written by Chris White ([Blog](http://reassembler.blogspot.co.uk/), [Twitter](https://twitter.com/djyt)). 


Installation
---------------

This port requires macOS 10.15
* Download the latest release from GitHub. 
* Copy the CannonBall application off the .dmg into somewhere else.

You will **need** to provide your own OutRun game data:
* Launch CannonBall at least once to perform initial setup.
* Navigate to `~/Library/Application Support/CannonBall`
* Insert game data into the `roms` folder, following the instructions in `roms/roms.txt`

**The game doesn't open! Something about an unidentified developer?** This is because the game isn't signed by Apple. Hold the Option key, then Open the game. You'll need to do this only once.

**The game crashes when launched!**
This is probably because of incomplete ROM data. Double check that all the required ROMs are present in `~/Library/Application Support/CannonBall/roms` and try again.

If the issue persists, open an issue in this repository with the crash report.


Development
---------------

CannonBall is coded in C++ and makes use of the SDL 2 and Boost libraries. 
**Do not use this fork to port to other platforms.** Please use the original repository instead. 

* Install Xcode.
* Install the [Boost Library](http://www.boost.org/) with Homebrew, or any other method.
* Install the [SDL Development Library](https://www.libsdl.org/download-2.0.php) with Homebrew, or any other method.
* Extract the CannonBall code somewhere.
* Launch the .xcodeproj, add the necessary frameworks to the project.
* Build.
