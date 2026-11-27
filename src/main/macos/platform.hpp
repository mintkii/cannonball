//
//  platform.hpp
//  CannonBall
//
//  Created by Kii on 2026-10-23.
//
#pragma once

#include <string>

namespace platform
{
    // Starts SDL's video subsystem and adds About and Settings to its menu bar.
    void init();

    // Ask the user to put the ROMs in path.
    std::string ask_for_rom_folder(const std::string& path);
}
