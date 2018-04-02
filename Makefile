#!/usr/bin/env make
## Makefile to generate SSL certificates and postfix configuration
## instructions and files for secure TLS based SMTP relaying.
##
## Usage:
## 1. customize settings.mk
## 2. from a terminal run:
##  make
##
## To start over run:
##  make clean && make
##
## Concepts
## 1. the (internal) sending server called `smtp-client' is assumed
##    to have a dynamic external IP address
## 2. the (internet connected) relayhost called `smtpd-server' is
##    assumed to have a static external IP address

## from http://www.postfix.org/postconf.5.html#smtpd_tls_cert_file (or man postconf):
##
##  To enable a remote SMTP client to verify the Postfix SMTP server
##  certificate, the issuing CA certificates must be made available to
##  the client. You should include the required certificates in the
##  server certificate file, the server certificate first, then the
##  issuing CA(s) (bottom-up order). Example: the certificate for
##  "server.example.com" was issued by "intermediate CA" which itself
##  has a certificate of "root CA". Create the (fullchain) server.pem
##  file with:
##   `cat server_cert.pem intermediate_CA.pem root_CA.pem > server.pem".
##  .
##  If you also want to verify client certificates issued by these CAs,
##  you can add the CA certificates to the smtpd_tls_CAfile, in which
##  case it is not necessary to have them in the smtpd_tls_cert_file or
##  smtpd_tls_dcert_file.
##  .
##  A certificate supplied here must be usable as an SSL server
##  certificate and hence pass the
##   `openssl verify -purpose sslserver ...' test.
##
## This script uses the smtpd_tls_CAfile so no fullchain server
## certificate is required

## smtpd_tls_security_level (default: empty):
##  The SMTP TLS security level for the Postfix SMTP server; when a
##  non-empty value is specified, this overrides the obsolete
##  parameters `smtpd_use_tls' and `smtpd_enforce_tls'. This parameter is
##  ignored with "smtpd_tls_wrappermode = yes".
##  Specify one of the following security levels:
##  none:    TLS will not be used.
##  may:     Opportunistic TLS: announce STARTTLS support to remote SMTP
##           clients, but do not require that clients use TLS
##           encryption.
##  encrypt: Mandatory TLS encryption: announce STARTTLS support to
##           remote SMTP clients, and require that clients use TLS
##           encryption. According to RFC 2487 this MUST NOT be
##           applied in case of a publicly-referenced SMTP
##           server. Instead, this option should be used only on
##           dedicated servers.
##  Note 1:  The "fingerprint", "verify" and "secure" levels are not
##           supported here. The Postfix SMTP server logs a warning and
##           uses "encrypt" instead. To verify remote SMTP client
##           certificates, see TLS_README for a discussion of the
##           smtpd_tls_ask_ccert, smtpd_tls_req_ccert, and
##           permit_tls_clientcerts features.
## Note 2:   The parameter setting "smtpd_tls_security_level = encrypt"
##           implies "smtpd_tls_auth_only = yes".
## Note 3:   When invoked via "sendmail -bs", Postfix will never offer
##           STARTTLS due to insufficient privileges to access the
##           server private key. This is intended behavior.
## This feature is available in Postfix 2.3 and later.

app_name			:= postfix-tls-based-relaying
app_remote_root			:= /etc/${app_name}
## set in settings.mk
days	   			:= 
ca_key_bits			:= 
ca_key_cipher			:=
csr_digest  			:=

domain	   			:= 
cert_req_country		:= 
cert_req_state			:= 
cert_req_locality		:= 
cert_req_organization		:= 
cert_req_ou			:= 
ca_cert_req_cn			:= 
signature_hash			:= 
smtp_client_hostname  		:= 
smtp_client_fqdn		:= 
smtp_client_ssh_user		:=
smtp_client_tls_loglevel	:=
smtpd_server_hostname 		:= 
smtpd_server_ssh_user		:= 
smtpd_server_fqdn		:= 
smtpd_server_port		:= 
smtpd_server_relay_clientcerts_in	:=
smtpd_server_tls_loglevel 	:=

include settings.mk

## store the passphrase to create and use openssl private keys in a gpg encrypted file
certs_passphrase_file		:= ${HOME}/.${smtpd_server_hostname}-${smtp_client_hostname}-passphrase.gpg

## real and virtual output paths
remote_certs_rootdir		:= /etc/${app_name}
rel_postfix_conf_dir		:= etc/postfix
abs_postfix_conf_dir		:= /${rel_postfix_conf_dir}
local_certs_rel_rootdir		:= certs
certs_ca_dirname		:= ca
certs_smtp_client_dirname	:= smtp-client
certs_smtpd_server_dirname	:= smtpd-server
local_certs_ca_path		:= ${local_certs_rel_rootdir}/${certs_ca_dirname}
local_certs_smtp_client_path	:= ${local_certs_rel_rootdir}/${certs_smtp_client_dirname}
local_certs_smtpd_server_path	:= ${local_certs_rel_rootdir}/${certs_smtpd_server_dirname}
remote_certs_ca_path		:= ${remote_certs_rel_rootdir}/${certs_ca_dirname}
remote_certs_smtp_client_path	:= ${remote_certs_rel_rootdir}/${certs_smtp_client_dirname}
remote_certs_smtpd_server_path	:= ${remote_certs_rel_rootdir}/${certs_smtpd_server_dirname}

ca_name	   			:= ${domain}-ca
ca_key  			:= ${local_certs_ca_path}/${ca_name}.key.pem
ca_crt	 			:= ${local_certs_ca_path}/${ca_name}.crt.pem

## smtp client keys
##  value for the CN (common name) used
smtp_client_cert_req_cn		:= ${smtp_client_fqdn}
## private rsa key used to create the csr
smtp_client_key 		:= ${local_certs_smtp_client_path}/${smtp_client_fqdn}.key.pem
## certificate signing request
smtp_client_csr			:= ${local_certs_smtp_client_path}/${smtp_client_fqdn}.csr.pem
## self signed certificate
smtp_client_crt			:= ${local_certs_smtp_client_path}/${smtp_client_fqdn}.crt.pem

## smtpd server keys
##  value for the CN (common name) used
smtpd_server_cert_req_cn	:= ${smtpd_server_fqdn}
## private rsa key used to create the csr
smtpd_server_key 		:= ${local_certs_smtpd_server_path}/${smtpd_server_fqdn}.key.pem
## certificate signing request
smtpd_server_csr 		:= ${local_certs_smtpd_server_path}/${smtpd_server_fqdn}.csr.pem
## self signed certificate
smtpd_server_crt		:= ${local_certs_smtpd_server_path}/${smtpd_server_fqdn}.crt.pem
## path of the file on the smtpd server containing the fingerprint of the smtp client  
smtpd_server_client_signature_src := ${rel_postfix_conf_dir}/relay_clientcerts
smtpd_server_client_signature_remote_src := ${abs_postfix_conf_dir}/relay_clientcerts
smtpd_server_client_signature_remote_db  := ${abs_postfix_conf_dir}/relay_clientcerts.db

app_comment_start		:= start config generated by ${app_name}
app_comment_end			:= end config generated by ${app_name}


.PHONY: local live smtpd-server-relay-clientcerts_db rsync clean instruction smtp-client-instruction smtpd-server-instruction ca-key ca-crt smtp-client-key smtp-client-csr smtp-client-crt smtp-client-signature smtpd-server-signature smtpd-server-client

local: smtp-client-instruction smtpd-server-instruction

live: local rsync smtpd-server-relay-clientcerts_db

testssl.sh:
	git clone "https://github.com/drwetter/testssl.sh.git"

ca-key: ${ca_key}
ca-crt: ${ca_crt}
smtp-client-key: ${smtp_client_key}
smtp-client-csr: ${smtp_client_csr} 
smtp-client-crt: ${smtp_client_crt} 
smtpd-server-key: ${smtpd_server_key} 

${local_certs_rel_rootdir}:
	mkdir -p $@

${local_certs_ca_path} ${local_certs_smtp_client_path} ${local_certs_smtpd_server_path} ${rel_postfix_conf_dir}: ${local_certs_rel_rootdir} 
	mkdir -p $@

${ca_key}: ${local_certs_ca_path} ${local_certs_smtp_client_path} ${local_certs_smtpd_server_path} ${rel_postfix_conf_dir}
	@echo 
	@echo "+++ 1. Generating the ${ca_key_bits} bit passphrase protected ${ca_key_cipher}"
	@echo "       RSA Private Key \`$@' for self-signing the root CA"
	gpg -d ${certs_passphrase_file} | openssl genrsa -${ca_key_cipher} -passout stdin -out $@ ${ca_key_bits}
	chmod 0700 $@

${ca_crt}: ${ca_key}
	@echo 
	@echo "+++ 2. Generating the self-signed ${csr_digest} root CA certificate \`$@'"
	@echo "       using the RSA Private Key \`$<'"
	gpg -d ${certs_passphrase_file} | openssl req -new -x509 -days ${days} -${csr_digest} -subj "/C=${cert_req_country}/ST=${cert_req_state}/L=${cert_req_locality}/O=${cert_req_organization}/OU=${cert_req_ou}/CN=${ca_cert_req_cn}" -passin stdin -key $< -out $@

${smtp_client_key}: ${ca_crt}
	@echo 
	@echo "+++ 3. Generating the ${bits} bit RSA private key \`$@' for ${smtp_client_fqdn}"
	openssl genrsa -out $@ ${bits}

${smtp_client_csr}: ${smtp_client_key}
	@echo
	@echo "+++ 4. Generating the ${csr_digest} csr \`$@' using"
	@echo "       the RSA private key \`$<' for ${smtp_client_fqdn}"
	openssl req -new -nodes -subj "/C=${cert_req_country}/ST=${cert_req_state}/L=${cert_req_locality}/O=${cert_req_organization}/OU=${cert_req_ou}/CN=${smtp_client_cert_req_cn}" -key $< -out $@

${smtp_client_crt}: ${smtp_client_csr} 
	@echo
	@echo "+++ 5. Generating the self-signed ${csr_digest} certificate \`$@' using"
	@echo "       the csr \`$<' for ${smtp_client_fqdn}"
	gpg -d ${certs_passphrase_file} | openssl x509 -req -CA ${ca_crt} -CAkey ${ca_key} -days ${days} -passin stdin -in $< -out $@ -CAcreateserial

smtp-client-instruction: ${smtp_client_crt}
	@echo 
	@echo "1. On smtp client ${smtp_client_fqdn} add to '/etc/postfix/main.cf':"
	@echo "cat >> /etc/postfix/main.cf << EOF"
	@echo "## >> ${app_comment_start}"
	@echo "##  make sure smtp client tries to start a TLS connection"
	@echo "smtp_enforce_tls    = yes"
	@echo "## define loglevel for smtp client to smtpd server TLS communication"
	@echo "smtp_tls_loglevel   = ${smtp_client_tls_loglevel}"
	@echo "##  smtpd server to relay outgoing email to (use square brackets to "
	@echo "##  prevent DNS MX lookups)"
	@echo "relayhost           = [${smtpd_server_fqdn}]:${smtpd_server_port}"
	@echo "##  point smtp client to the right custom CA certificate"
	@echo "smtp_tls_CAfile     = ${app_remote_root}/${ca_crt}"
	@echo "##  use the client's certificate: smtp_tls_cert_file = smtp_client_csr signed by ca_crt"
	@echo "smtp_tls_cert_file  = ${app_remote_root}/${smtp_client_key}"
	@echo "##  use the client's unencrypted private key"
	@echo "##  (= signed certificate = smtp_client_csr signed by ca_crt)"
	@echo "smtp_tls_key_file   = ${app_remote_root}/${smtp_client_crt}"
	@echo "## << ${app_comment_end}"
	@echo "EOF"
	@echo 
	@echo "2. rsync the cert tree to the smtp client server:"
	@echo "rsync -av ${local_certs_rel_rootdir}/* ${smtp_client_ssh_user}@${smtp_client_fqdn}:${app_remote_root}/"


${smtpd_server_key}: ${ca_crt}
	@echo 
	@echo "+++ 3. Generating the ${bits} bit RSA private key \`$@' for ${smtpd_server_fqdn}"
	openssl genrsa -out $@ ${bits}

${smtpd_server_csr}: ${smtpd_server_key}
	@echo
	@echo "+++ 4. Generating the ${csr_digest} csr \`$@' using"
	@echo "       the RSA private key \`$<' for ${smtpd_server_fqdn}"
	openssl req -new -nodes -subj "/C=${cert_req_country}/ST=${cert_req_state}/L=${cert_req_locality}/O=${cert_req_organization}/OU=${cert_req_ou}/CN=${smtpd_server_cert_req_cn}" -key $< -out $@

${smtpd_server_crt}: ${smtpd_server_csr} 
	@echo
	@echo "+++ 5. Generating the self-signed ${csr_digest} certificate \`$@' using"
	@echo "       the csr \`$<' for ${smtpd_server_fqdn}"
	gpg -d ${certs_passphrase_file} | openssl x509 -req -CA ${ca_crt} -CAkey ${ca_key} -days ${days} -passin stdin -in $< -out $@ -CAcreateserial

smtpd-server-relay-clientcerts_db: ${smtpd_client_crt}
	ssh ${smtpd_server_fqdn} -- "openssl x509 -${signature_hash} -fingerprint -in $< | head -1 | awk -F\= '{print $$2}') ${smtp_client_fqdn}  > ${smtpd_server_relay_clientcerts_in} && cd /etc/postfix && postmap ${smtpd_server_relay_clientcerts_in} && postfix reload"

smtpd-server-instruction: ${smtp_client_crt}
	@echo
	@echo "3. on smtpd server ${smtpd_server_fqdn} add ${signature_hash}"
	@echo "   signature of smtp-client ${smtp_client_key}"
	@echo "   to '${smtpd_server_relay_clientcerts_in}' and generate '${smtpd_server_relay_clientcerts_in}.db':"
	@echo "echo $(shell openssl x509 -${signature_hash} -fingerprint -in $< | head -1 | awk -F\= '{print $$2}') ${smtp_client_fqdn}  > ${smtpd_server_relay_clientcerts_in} && postmap ${smtpd_server_relay_clientcerts_in}"
	@echo
	@echo "4. on smtpd server ${smtpd_server_fqdn} add to '/etc/postfix/master.cf':"
	@echo "cat >> /etc/postfix/master.cf << EOF"
	@echo "## >> ${app_comment_start}"
	@echo "## proper order if restrictions:"
	@echo "##   1: client, 2: helo, 3: sender, 4: relay, 5: recipient, 6: data or end-of-data"
	@echo "## When a restriction list (eg. client) evaluates to REJECT or" 
	@echo "## DEFER the restriction lists that follow (eg. helo, sender, etc.) are skipped."
	@echo "# =========================================================================="
	@echo "# service type  private unpriv  chroot  wakeup  maxproc command + args      "
	@echo "#               (yes)   (yes)   (no)    (never) (100)                       "
	@echo "# =========================================================================="
	@echo "## add \`-v' to smtpd command below to debug handling of permit/reject rules "
	@echo "# 2500      inet  n       -       n       -       -       smtpd -v"
	@echo "2500      inet  n       -       n       -       -       smtpd"
	@echo "## define loglevel for smtpd server to smtp client TLS communication"
	@echo "   -o smtpd_tls_loglevel=1"
	@echo "## mandatory TLS encryption: announce STARTTLS support"
	@echo "## to remote SMTP clients, and require that clients use TLS encryption"
	@echo "   -o smtpd_tls_security_level=encrypt"
	@echo "## explicitly ask for a trusted remote smtp client certificate"
	@echo "   -o smtpd_tls_ask_ccert=yes"
	@echo "## point smtp client to the right custom root CA"
	@echo "   -o smtpd_tls_CAfile=${app_remote_root}/${ca_crt}"
	@echo "## use the signed (non full-chain) server certificate"
	@echo "   -o smtpd_tls_cert_file=${app_remote_root}/${smtpd_server_key}"
	@echo "## use the generated non-encrypted private key for smtpd"
	@echo "   -o smtpd_tls_key_file=${app_remote_root}/${smtpd_server_crt}"
	@echo "## allowed client certificate database:"
	@echo "   -o relay_clientcerts=hash:${smtpd_server_relay_clientcerts_in}"
	@echo "## override postfix relay-safe defaults"
	@echo "   -o smtpd_client_restrictions="
	@echo "   -o smtpd_helo_restrictions="
	@echo "   -o smtpd_sender_restrictions="
	@echo "## only permit relaying for trusted TLS clients"
	@echo "   -o smtpd_relay_restrictions=permit_tls_clientcerts,reject"
	@echo "## override postfix relay-safe defaults"
	@echo "   -o smtpd_recipient_restrictions="
	@echo "   -o smtpd_data_restrictions="
	@echo "## TODO: unsure"
	@echo "   -o smtpd_reject_unlisted_recipient=no"
	@echo
	@echo "## << ${app_comment_end}"
	@echo "EOF"
	@echo
	@echo "5. rsync the cert tree to the smtpd server:"
	@echo "rsync -av ${local_certs_rel_rootdir} ${smtpd_server_ssh_user}@${smtpd_server_fqdn}:${app_remote_root}/"
	@echo
	@echo "6. restart both postfix instances"



rsync: smtp-client-instruction smtpd-server-instruction
	@echo "rsyncing the certificate tree to the smtp client server \`${smtp_client_fqdn}'"
	rsync -av ${local_certs_rel_rootdir} "${smtp_client_ssh_user}@${smtp_client_fqdn}:${app_remote_root}/"
	@echo "rsyncing the certificate tree to the smtpd server \`${smtpd_server_fqdn}'"
	rsync -av ${local_certs_rel_rootdir} "${smtpd_server_ssh_user}@${smtpd_server_fqdn}:${app_remote_root}/"


smtpd-server-client: ${smtpd_server_client_signature_remote_db}

${smtpd_server_client_signature_remote_db}: /${smtpd_server_client_signature_src}
	ssh ${smtpd_server_ssh_user}@${smtpd_server_fqdn} -- postmap $<

${smtpd_server_client_signature_remote_src}: ${smtpd_server_client_signature_src}
	rsync -av $< "${smtpd_server_ssh_user}@${smtpd_server_fqdn}:$@"

signature: ${smtpd_server_client_signature_src}
	@cat $<

${smtpd_server_client_signature_src}: ${smtp_client_crt}
	@echo "$(shell openssl x509 -${signature_hash} -fingerprint -in $< | head -1 | awk -F\= '{print $$2}') ${smtp_client_fqdn}" > $@


check-smtp-client:
	@echo
	@echo "checking relevant postfix configuration parameters for smtp client ${smtp_client_fqdn}:"
	ssh ${smtp_client_ssh_user}@${smtp_client_fqdn} -- grep -E "^[^#].*smtp[d]*_tls\|^[^#].*relay[a-z_]+" /etc/postfix/{main,master}.cf

check-smtpd-server:
	@echo
	@echo "checking relevant postfix configuration parameters for smtpd server ${smtpd_server_fqdn}:"
	ssh ${smtpd_server_ssh_user}@${smtpd_server_fqdn} -- grep -E "^[^#].*smtp[d]*_tls\|^[^#].*relay[a-z_]+" /etc/postfix/{main,master}.cf


check: check-smtp-client check-smtpd-server

clean:
	rm -rf ${local_certs_rel_rootdir} testssl.sh


lies:
	@echo Hoi ik ben Lies en ben 10 jaar

