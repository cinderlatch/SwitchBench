#ifndef HACPACK_RSA_H
#define HACPACK_RSA_H

#include <inttypes.h>

void rsa_sign(void* input, size_t input_size, unsigned char* output, size_t output_size, char* rsa_private_key);
void rsa_sign_with_file(void* input, size_t input_size, unsigned char* output, size_t output_size, char* keypath);
const unsigned char *rsa_get_acid_public_key();
const char *rsa_get_acid_private_key();

#endif