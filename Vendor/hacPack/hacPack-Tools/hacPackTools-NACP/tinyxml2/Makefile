# For GNU conventions and targets see https://www.gnu.org/prep/standards/standards.html
# Using GNU standards makes it easier for some users to keep doing what they are used to.

# 'mkdir -p' is non-portable, but it is widely supported. A portable solution
# is elusive due to race conditions on testing the directory and creating it.
# Anemic toolchain users can sidestep the problem using MKDIR="mkdir".

AR = ar
ARFLAGS = cr
RM = rm -f
RANLIB = ranlib

all: staticlib

clean:
	-$(RM) *.o libtinyxml2.a

staticlib: libtinyxml2.a

libtinyxml2.a: tinyxml2.o
	$(AR) $(ARFLAGS) $@ $^
	$(RANLIB) $@

tinyxml2.o: tinyxml2.cpp tinyxml2.h
