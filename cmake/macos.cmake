# -----------------------------------------------------------------------------
# CannonBall macOS Setup
# -----------------------------------------------------------------------------

# Use OpenGL for rendering.
find_package(OpenGL REQUIRED)
set(OPENGL 1)

# Find Homebrew libraries.
set(lib_base /opt/homebrew/include)

# Link CoreFoundation
find_library(COREFOUNDATION_LIBRARY CoreFoundation)

# The project uses Boost by #include <boost/...>,
# so make sure to be at the right directory level.
set(boost_dir ${lib_base})
set(sdl2_dir ${lib_base}/sdl2)

# Platform Specific Libraries
set(platform_link_libs
    ${OPENGL_LIBRARIES}
    ${COREFOUNDATION_LIBRARY}
)