# -----------------------------------------------------------------------------
# CannonBall macOS Setup
# -----------------------------------------------------------------------------
EXECUTE_PROCESS( COMMAND uname -m COMMAND tr -d '\n' OUTPUT_VARIABLE ARCHITECTURE )
message( STATUS "Architecture: ${ARCHITECTURE}" )

# Set C++ compiler flags to specify architecture
# and set the SDK path for macOS.
set(CMAKE_CXX_FLAGS " -arch ${ARCHITECTURE} -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")

# Use OpenGL for rendering.
find_package(OpenGL REQUIRED)
set(OPENGL 1)

# Find Homebrew libraries.
set(lib_base /opt/homebrew/include)

# The original project files use Boost by writing
# #include <boost/...> in the source files. This is
# contradictory to how SDL is included, therefore
# destroying my sanity and making me do this.
set(boost_dir ${lib_base})
# I guess it's legal.

set(sdl2_dir ${lib_base}/sdl2)

# Platform Specific Libraries
set(platform_link_libs
    ${OPENGL_LIBRARIES}
)