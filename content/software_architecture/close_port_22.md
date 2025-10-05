---
title: "Close Port 22!"
date: 2025-10-04
summary: "cloudflare"
description: ""
tags: ["Kubernetes", "Cloudflare"]
toc: false
---

Traditionally, network administrators restricted servers to only accept incoming traffic on port 22
for ssh to protect servers from the dangers of the internet. Some tried to improve their setup with
a "security by obscurity" approach and moved the port that runs ssh from its default to an
unexpected port. Then some added the creative approach of running 'Fail2Ban' or 'endlessh' on port 22, or
they even set up honeypots like 't-pot' that allows to watch how attackers try to gain access to one's
infrastructure.
Some mitigated the risk by running jumpbox servers. In such approaches, there is one jumpbox server
which is open to the world wide web but which only has the purpose of accessing the actual
infrastructure via a private network. The jumpbox server could be protected by the current openssh
protocols and hardware keys.

Of course, these approaches are perfectly valid. While ssh-key setups had issues, such as the XZ Utils
backdoor / supply-chain incident in 2024 (a malicious backdoor was inserted into the xz / liblzma project such that, when used on systems that build OpenSSH with certain systemd dependencies, the backdoor allowed bypassing SSH authentication) ssh-key setups are generally safe unless you are the kind of target that would not benefit from such a blog post anyway.
However, what might be the most critical weakness in traditional public-private key setups is - as
always - not the technology itself but the organizational burden and human error. Countless hours
are spent by admins every day to authorize ssh-keys of new hires on old and new servers.
Big corporations have Ansible (or other) scripts for setting this up. However, for most companies, it
is much easier to hire an admin for this housekeeping. Also, scripts that automatically add ssh
key pairs are one of the most interesting pieces of code in an organization for any attacker.
Even if everything is configured correctly on many production servers, the files that store
authorized keys are a mess and some keys live in these files for months or even years. 
Rotating them is in many setups associated with a lot of manual work. The situation is usually even much worde in testing and development environments.

It is time to tidy this chaos. It is time to replace traditional ssh-keys with ephemeral SSH
certificates. It is time to block port 22 in the firewalls. We need a proper open source solution
for this but in the meantime Cloudflare SSH for infrastructure solves these fundamental problems.
There are many open source projects (such as Pangolin, Teleport, Octelium and others)·that cover many of the requirements. 
However Cloudflare is like a valid option if your setup-philosophy does not insist on OSS only.

In the following paragraphs we will walk through the practical setup of Cloudflare SSH access for
infrastructure. Generally, one has to follow the Cloudflare docs
[SSH with Access for Infrastructure](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/use-cases/ssh/ssh-infrastructure-access/). 
However, if you have setup the zerotrust environment from scratch some extra information might be helpful. This
is what this blogpost is for. It will mirror the docs referenced above and is complementary. You
will be able to set this up just by following this blogpost but it is certainly helpful to keep
Cloudflares documentation open while working on this.

**Please note:
Steps 1-3 are global setup (WARP client policies, split tunnel config, TCP proxying) - unless specific configurations are required, there is no need to repeat them for each new server.
Steps 4,5, 7 are per-server setup (Target, Application, CA trust on the server) - they need to be repeated for each new host
Step 6 (Gateway precedence) is global and does most likely not need to be adjusted in a loose
development/testing environment (but this highly depends on the infrastructure context)**


## 1. Connect the Server to Cloudflare Zerotrust
The servers that we want to access via Cloudflare ssh access need to run a Cloudflare Zerotrust
tunnel. It works both from remotely-managed (I recommend this if your setup allows it) and locally-managed tunnels.
If you have not configured a tunnel yet you may do so by following the instructions [here](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) 

## 2. Set up the WARP client (ON THE LOCAL DEVICE)
The WARP client is a program running on the local device that connects the local machine with
Cloudflare's global network. As we run it in conjunction with Zerotrust it also allows to enforce
Zerotrust policies that have granular control over under what conditions a device can connect.


**Install WARP**
The install can be done either manually or by applying a managed deployment by using some MDM tool.
You can download a stable release from
[here](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/download-warp/).
If you work on Mac you may also make use of homebrew. During the login process you will be asked for
your team domain as in 'domainname.cloudflareaccess.com'.
If you are not sure about your team name you can find it in Zero Trust under Settings > Custom Pages.
Turn off any VPN service that might be running on the local device as this might interfere with the WARP client.

**Enable the Gateway proxy for TCP**
Zero Trust -> Settings -> Network (not "Networks" on the menubar) -> Firewall -> Proxy

**Create device enrollment rules**
Zero Trust -> Settings -> WARP client
You can also set here if you want to allow the users to update their client independently

## 3. Route server IPs through WARP
Cloudflare WARP is a user-side network client (VPN-like). It encrypts and routes a user's traffic through Cloudflare's network for policy enforcement (DNS-filtering, Access rules, etc.).
WARP has a default exception list called 'Split Tunnels'. In the 'Exclude mode' certain address ranges are NOT sent to Cloudflare.
Instead they go directly to the local network.
The defaults for these exceptions are private IP spaces (RFC 1918). Such IP spaces usually point to printers, NAS, or other LAN resources that are not part of the Internet.
As a reminder - these RFC 1918 ranges are:

- 10.0.0.0/8
- 172.16.0.0/12
- 192.168.0.0/16

This has the following implications for our setup:
If the SSH server has a public IP (e.g. 91.97.141.240) that IP is not RFC1918, so WARP will send traffic to Cloudflare.
A private IP (e.g. 172.31.15.42) that falls under RFC1918 will be excluded by WARP by default.
Practical example:
If a user runs ssh user@172.31.15.42 WARP will try to connect that user directly via LAN (bypassing Cloudflare). So, if a user runs ssh user@172.31.15.42 the Zero Trust Application policies are never applied. In case the SSH server lives at a private IP, WARP will not route that traffic to Cloudflare unless the default Split tunnel settings are overriden.
If one deals with public IPs the IPs in question are not RFC1918. Therefore, no changes to the Split Tunnel are required. Only if we had a ssh server on a private IP changes to these settings would be required. If you have to configure it go to:
Zerotrust -> Settings -> WARP Client -> Device Settings -> Select Profile Name to Change -> Split Tunnels


-------------------
**Please note: steps 1-3 do not need to be done for adding new servers (unless specific configurations are required)
For adding new servers with the WARP-ssh approach follow steps 4-8**

-------------------

## 4. Add a target
Targets are protocol-agnostic, therefore we do not need to configure a new target for each protocol.
When we want to add ssh-access to new servers we add them as targets and provide their IP-address here.
However, before we can add a target, we need to create a CIDR route (unless it is already configured).

**Adding a new server for SSH access**
In principle the following needs to be done: 
Create a target for the server in Zero Trust → Networks → Targets.
However, if the tunnel has no CIDR, no IP-address can be selected in the Target. Please note, it is normal that one has to type in the full IP-address before the GUI-Dropdown recognizes it. However, if no CIDR is defined even after inserting the full IP-address you can not select the tunnel from the dropdown.
If the target IP does not appear in the dropdown, go to Networks -> Routes and confirm that the IP routes through Cloudflare Tunnel.

Once the route is defined that way, it is selectable from the dropdown when creating a target (but as outlined above, you first need to insert the entire IP-address before you can select it).

In order to add a target the server that is selected as the target needs a CIDR.
If the server has a public IP (e.g. 91.98.140.230), then add a /32 CIDR route:
91.98.140.230/32
This declares: “Traffic to exactly this IP goes into this tunnel.”
Please note: you can add the CIDR route either from "Routes" as described above or from the "Tunnels" menu in Zerotrust.

**A note on private IPs**
CIDRs in Cloudflare Tunnels are routing hints for Cloudflare, not changes server networking (such as private networks).
CIDRs apply only to Cloudflare's routing decisions. They do not alter the Linux network configuration of the server, nor do they interfere with your provider's internal routing.
Best practice is to use /32 per server to avoid ambiguity (if the server has a private IP in your network (e.g. 10.x.x.x or 172.31.x.x).
The CIDRs live in Cloudflare’s control plane, not on the actual server.

## 5. Add an infrastructure application
Please note that Cloudflare does NOT create linux users on the target servers. The users need to exist already (unless we have a script that performs all these steps automatically using terraform and also create the users on the target machine, while this is possible, I do not see that we will setup such automations in the near future).
As the screen shows after having added the application - we now need to configure our target server to trust the Cloudflare SSH CA.

On your local machine (that has WARP running) you can run the following command to assert what targets are accessible from WARP.

```shell
warp-cli target list
```
This will give an output like this:

```shell
localmachine ~ % warp-cli target list
# Output
╭──────────────────────────────────────┬──────────┬──────┬───────────────────────────┬──────────────────────────┬────────────────────────────────────────────╮
│ Target ID                            │ Protocol │ Port │ Attributes                │ IP (Virtual Network)     │ Usernames (examples)                       │
├──────────────────────────────────────┼──────────┼──────┼───────────────────────────┼──────────────────────────┼────────────────────────────────────────────┤
│ 01224c4e-bd7f-7d39-8c61-08d247ev5bce │ SSH      │ 22   │ hostname: host-0          │ 91.92.138.240 (default)  │ root, service-account, cluster-admin       │
├──────────────────────────────────────┼──────────┼──────┼───────────────────────────┼──────────────────────────┼────────────────────────────────────────────┤
│ 015680c4-2325-7093-95ee-120a148ee137 │ SSH      │ 22   │ hostname: host-1          │ 188.262.143.36 (default) │ root, service-account, db-admin            │
╰──────────────────────────────────────┴──────────┴──────┴───────────────────────────┴─────────────────────────
```
The newly configured target should show up here.
Please note - when this is already configured and you try to ssh into that server using the ssh on port 22 setup and Cloudflare WARP is activated, the connection will not work.
Turn off Cloudflare WARP for a moment to regularly ssh into the server to perform step 7 (and 6 if required).

## 6. Modify order of precedence in Gateway
This is only required if you need to evaluate Access applications before or after Gateway policies,
so users pass the policies befroe the Access application gives access. Probably, you do not need to
change these settings for an initial proof of concept of this setup. If you do, please refer to
[Cloudflare's network
policies](https://developers.cloudflare.com/cloudflare-one/policies/gateway/network-policies/).


## 7. Configure SSH server
This step allows Access to authenticate using short-lived certificates instead of traditional SSH keys.
It requires to generate a Cloudflare SSH CA, saving the public key, editing the sshd_config on the target and then restarting the ssh server.
Please note that these steps require ssh-access to the target server (do not close port 22 before this step).

**Create an API token**
Create a Cloudflare API token with the following permissions. Please note that Edit rights do NOT automatically give you Read rights (read further below for detailed reference).
Type	Item	Permission
Account	Access: SSH Auditing	Edit

Type	Item	Permission
Account	Access: SSH Auditing	Read

You then need to retrieve the ACCOUNT_ID. Then continue on the server you want to ssh into with the following commands:

```shell
export CLOUDFLARE_API_TOKEN="tokenhere"
export ACCOUNT_ID="accountidhere"

# This POST command will probably tell you (if the SSH Certificate Authority (CA) has been created before):
# "message": "access.api.error.gateway_ca_already_exists"

curl "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/access/gateway_ca" \
  --request POST \
  --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN"
  
# Therefore, use the GET command to list SSH Certificate Authorities (CA)
curl "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/access/gateway_ca" \
  --request GET \
  --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN"

# This will give an output like this:
{
  "result": {
    "id": "youridwillbeshownhere",
    "public_key": "ecd... open-ssh-ca@cloudflareaccess.org"
  },
  "success": true,
  "errors": [],
  "messages": []
}

# The 'public_key' will be required in the upcoming steps
# If you get an empty 'public_key' in the response read the paragraph below

```
--------------------
In case you do get an empty public key when running the GET request:
Please note that a token that has "Edit" rights does (apparently in some cases) NOT have read rights. When creating the public key using POST the public_key is returned (because it was just created). A subsequent GET may return an empty public_key because your token has Edit but not Read for Access: SSH Auditing. Some Cloudflare APIs will show object metadata under Edit, yet redact sensitive fields on GET unless Read is present. It took me some time to figure this out, I thought all the time something is off with my API-token settings. So, I hope this is of help to you.

-------------

Then follow the instructions from the docs on the server:
1. Create/Modify /etc/ssh/ca.pub and append the public_key, if you have several keys, keep them in separated lines
2. Modify the sshd_config file:
	 Add the following to the top of the /etc/ssh/sshd_config in sudo)
   Please note - if there are include statements below (such as 'Include /etc/ssh/sshd_config.d/.conf'  the configurations in those files will not take precedence.
   
```shell
PubkeyAuthentication yes
TrustedUserCAKeys /etc/ssh/ca.pub
```
3. Reload the ssh server for the sshd_config to take effect
```shell
sudo systemctl reload ssh
```

## 8. Connect as user and ensure accessibility
Now you can try to login as user from a local machine while Cloudflare Zerotrust is turned on.

```shell
ssh user@ipaddressofsshserver
```
Test the connection with activated WARP (should be able to connect) and with deactivated WARP Zerotrust (should not work).

**Handling Host Key Changes after Enabling Cloudflare WARP SSH Access**
When enabling SSH access through Cloudflare WARP and Access for Infrastructure that has been accessed from the local device before, clients may encounter the following warning upon connecting to a server:
```shell
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
```

This occurs because the SSH connection path has changed. Previously, the client connected directly to the server and recorded the server’s original host key in ~/.ssh/known_hosts. After enabling WARP and Access, the client now sees a different host key (presented by the Cloudflare SSH proxy). SSH correctly warns that the host identification has changed but the warning indicates no danger in this case.
Mitigate this by:
```shell
# Remove the outdated key entry for the server’s IP or hostname
ssh-keygen -R <server_ip>

# Reconnect while WARP is enabled. SSH will prompt to accept the new key:
ssh -o StrictHostKeyChecking=ask <user>@<server_ip>

# The new key will be stored in known_hosts, and future logins will proceed without warnings
```

If the ssh-connection behavior behaves as described above, port 22 on the server can be closed.
Verify that the port is closed:

```shell
nmap -Pn -p- 22 ip-address-of-server
```
This command should verify the closed port.

## Preserve Break-Glass ssh access
Now you have closed port 22 and cloudflare is your ssh-key authority. However, it makes sense to
keep one ssh-key configured, to allow a connection in case something happens to Cloudflare
(unlikely but not impossible). With that approach, you can give your engineers (and yourself)
granular access to your infrastructure using Cloudflare on a day to day basis but keep access in
case the tunnel breaks. In that case, you can simply open up port 22 and make use of your configured
key.

## Conclusion
If you followed the instructions you have a server-setup that is not reachable via ingress (given
your firewall works as expected). While this does not protect you from firewall misconfigurations
or malicious input you accept on the servers (e.g. a webapp that allows input and is published via
Cloudflare World Edge) it does enhance the security of your infrastructure significantly compared to
an open port 22 that allows ssh-connections. It also provides granular control over who is allowed
to connect to your servers while enforcing updated policies almost in real-time (depending on your
settings for the time a certificate is valid). May your servers be safe.



