#ifndef HPTNACP_UTILS_H
#define HPTNACP_UTILS_H

#include <iostream>
#include <sstream>
#include <iomanip>
#include <string>
#include <cstdint>

template <typename T>
std::string uint_to_hex(T uint_value)
{
  std::stringstream ss;
  ss << "0x" << std::hex << std::setfill ('0') << std::setw(sizeof(T)*2) << uint_value;
  return ss.str();
}

#endif