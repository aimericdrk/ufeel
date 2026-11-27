#ifndef SPEECHTOTEXT_COREAUDIODEVICES_HPP
#define SPEECHTOTEXT_COREAUDIODEVICES_HPP

#include <functional>

auto watchCoreAudioDevices() -> std::function<bool()>;

#endif // SPEECHTOTEXT_COREAUDIODEVICES_HPP
