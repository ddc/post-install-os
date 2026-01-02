#!/usr/bin/env bash

wget -O git.tar.gz https://github.com/git/git/archive/v2.47.0.tar.gz
tar -xzvf git.tar.gz
cd git*/
make configure


#./configure --prefix=/opt/git
#make && make install
#ln -sf /opt/git/bin/* /usr/bin/


./configure --prefix=/home/ddc/Programs/git
make && make install
ln -sf /home/ddc/Programs/git/bin/* /home/ddc/bin/



rm -rf git.tar.gz
rm -rf git-2.47.0
