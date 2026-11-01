#include <algorithm>
#include <string>

inline std::string shout(std::string s) {
  std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return std::toupper(c); });
  return s;
}
