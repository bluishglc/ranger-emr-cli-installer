#!/bin/bash

# test hostname length

# test dns
$ hostname -f
$ nslookup $(hostname -f)
$ nslookup <ranger_fully_qualified_hostname> $ nslookup