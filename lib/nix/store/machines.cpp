#include "machines.h"
#include <nix/store/machines.hh>

const NixMachine** nix_store_machine_parse_config(const char** default_systems, size_t n_default_systems, const char* config, size_t config_len, size_t* out_len) {
  std::set<std::string> systems = {};

  for (size_t i = 0; i < n_default_systems; i++) {
    systems.insert(default_systems[i]);
  }

  std::string cfg(config, config_len);

  nix::Machines machines = nix::Machine::parseConfig(systems, cfg);
  *out_len = machines.size();
  return reinterpret_cast<const NixMachine**>(machines.data());
}
