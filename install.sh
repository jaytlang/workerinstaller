#!/bin/sh
# assuming a basic sane post-install configuration, configures the second (or
# third, or fourth etc.) worker machine based on the configuration of the first
# worker machine. assumes this first worker already has workerd running, and is
# routable from this machine

# CHANGEME 
user=fpga
first=eecs-digital-19.mit.edu
ram=6G
bundleserver=fpga3.mit.edu

# DONT CHANGE ANYMORE

copyfromfirst() {
	if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
		echo "usage: copyfromfirst source [dest]"
		return 1
	fi	

	[ -n "$2" ] || 2="."
	scp $user@$first:$1 $2
}

cat << EOF
===
Before continuing, ensure that this machine is registered
in /etc/relayd.conf on your relayd machine. If you have just
newly added it to /etc/relayd.conf, make sure you rerun the
bsdcert installer on the relayd machine to copy over the
appropriate certificates to this machine.

This installer may fail if certificates are not present, so
press any key only when you're sure that certificates have
been appropriately configured
===
EOF
read

echo "A.5.6... (check for /etc/ssl/server.pem)"
if [ ! -r /etc/ssl/server.pem ]; then
	cat << EOF
===
We couldn't read /etc/ssl/server.pem. This
means you probably didn't do the above step.
Please do that, and then come back here.
===
EOF
	exit 1
fi
	
echo "A.5.1... (pf.conf)"

cd
[ -d "pfinator2000" ] || git clone https://github.com/jaytlang/pfinator2000
cd pfinator2000; echo "workerd" | ./install.sh; cd ..

cat /etc/sysctl.conf | grep 'net.inet.ip.forwarding'
[ $? -ne 0 ] && { echo "updating /etc/sysctl.conf"; doas sh -c "echo 'net.inet.ip.forwarding=1' >> /etc/sysctl.conf"; }

echo "A.5.2... (login.conf/vmd)"

doas sed -i '/vmd/{n;N;s|16384M|1T|;}' /etc/login.conf
doas rcctl enable vmd "$quiet"
doas rcctl start vmd "$quiet"

echo "A.5.7... (workerd)"

git clone --recursive https://github.com/jaytlang/workerd
cd workerd

sed -i -E "s/memory[[:blank:]]+[0-9]+G/memory $ram/" etc/vm.conf

echo "copying VM images (this will take a while)"
mkdir -p images

[ -r images/base.qcow2 ] || copyfromfirst /home/_workerd/base.qcow2 images
[ -r images/vivado.qcow2 ] || copyfromfirst /home/_workerd/vivado.qcow2 images

copyfromfirst /etc/signify/bundled.pub etc/

make
doas make reinstall

cat << EOF
===
workerd successfully installed. running sanity check now.
you should expect to see lots of output below - if you see
a unit test failure, something is broken and you should talk to 
jay/joe
===
EOF

cd unit
sed -i -E "s/server_hostname[[:blank:]]*=.*/server_hostname = \"$bundleserver\"/" bundle/conf.py
make test_vm_helloworld
make clean_all

doas rcctl enable workerd
doas rcctl start workerd

cat << EOF
===
you can check whether things worked by heading over to your load balancer
and running the following command:

doas relayctl show hosts

you should see the machine you just set up listed as 'up' within around
ten seconds or so. if this doesn't work, check /var/log/daemon, or try
setting verbosity on workerd:

doas rcctl stop workerd
doas rcctl set workerd flags "-v"
doas rcctl start workerd

thanks!
===
EOF
