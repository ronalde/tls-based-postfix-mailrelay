# Makefile to generate SSL certificates and postfix configuration
# instructions and files for secure TLS based SMTP relaying.


## Usage

1. copy `settings.mk.example` to `settings.mk` and edit it:

```bash
cp settings.mk.example settings.mk
## edit settings.mk
```
2. store the openssl passphrase in a pgp encrypted file:

```bash
## the Makefile assumes it lives in:
passphrasefile=${HOME}/.${smtpd_server_hostname}-${smtp_client_hostname}-passphrase
echo "Y0ur h4rd T0 gU355 passphrase" > ${passphrasefile}
gpg -e -r yourmail@example.org ${passphrasefile} && rm ${passphrasefile}
```

3. run the make script:

```bash
make
```

To start over run:
```bash
make clean && make
```

## Concepts

1. `smtp-client`: the (internal) sending server, assumed
   to have a dynamic external IP address
2. `smtpd-server`: the (internet connected) relayhost, 
   assumed to have a static external IP address with a valid PTR reverse DNS record

Imagine you have a postfix server which gets a dynamic IP address from
your ISP. 

Using DDNS or some homegrown script it's perfectly possible to update
the DNS records for your MX record so that incoming mail is
handled perfectly, eg.:

```
;; dns zone file for example.org domain
;; mail exchanger record points to a hostname
@            in MX 10 mailhost.example.org
;; external IP address for mailhost A record for example.org domain is
;; updated by DDNS or homegrown script
mailhost     in A  1.2.3.4
```

The problem is that most ISP don't allow to create reverse PTR records
and/or block outgoing SMTP port 25. That makes it virtually
impossible to use the same host for sending mail using SMTP. 

To see if your internet connection suffers from this try the following
(ending the command with `CTRL+C`):

```bash
netcat -v mailly.debian.org 25
```

 NOTE: 
  you need to have `netcat` (or `nc`) installed; the current MX host
  for debian.org is used as an example, but any external MX host could
  be used (use `dig +noall +answer MX example.org +short`).


If the output doesn't resemble something like:

```
mailly.debian.org [82.195.75.114] 25 (smtp) open
220 mailly.debian.org ESMTP Exim 4.89 Mon, 02 Apr 2018 06:02:46 +0000
```

... but instead shows something like:

```
mailly.debian.org [82.195.75.114] 25 (smtp) open
220 ypsmtpproxy01.t-mobile.nl ESMTP Postfix
```

... it means you suffer from a blocked port, or your provider uses
NAT. This leads to `501 5.7.1 DSN support is disabled (in reply to RCPT TO
command)` errors in your mail log.

So your internal postfix server can't sent mail using SMTP on port 25
directly. You should therefore use or setup an external relay SMTP
host listing on a non-standard port, and route all outgoing email to
the specified port on that host.

But specifying a `relayhost` in your postfix `main.cf` file is problematic
too:

1. the relay server would either have to allow relaying based
   on the hostname alone (which is very unreliable) , or
2. you should have your DDNS script update the IP address of the
   allowed hosts in the Postfix configuration file of the relay
   server, which is error prone. And, if your DDNS fails or is too
   slow, that could potentially open up relaying for others using the
   same ISP, while blocking your bonafide attempts to send external
   mail.

Both problems can be fixed by using TLS authentication between the
internal and the relaying SMTP servers.

The idea is simple enough:

1. you create a custom CA and use that to generate signed SSL keys for
   the (sending) SMTP server (called `smtp client` here) and the
   relaying SMTP server (called `smtpd server`)
2. you configure your `smtpd server` to allow relaying for any TLS
   authenticated host, and to listen on an alternative port (like `2500`), and finally
3. you configure your `smtp client` to relay external email to the
   `smtpd server` using TLS authentication and the non-blocked port (eg `2500`).

### Relevant Postfix configuration settings for the smtp client (`mailhost.example.org`)

*  `/etc/postfix/main.cf`:
```
relayhost          = relayhost.example.org:2500
smtp_enforce_tls   = yes
smtp_tls_CAfile    = example.org-ca.crt.pem
smtp_tls_cert_file = mailhost.example.org.crt.pem
smtp_tls_key_file  = mailhost.example.org.key.pem
```

### Relevant Postfix configuration settings for the smtpd server (`relayhost.example.org`)

* `/etc/postfix/master.cf`:
```
2500      inet  n       -       y       -       -       smtpd
  -o smtpd_tls_security_level=encrypt
  -o smtpd_tls_ask_ccert=yes
  -o smtpd_tls_CAfile=example.org-ca.crt.pem
  -o smtpd_tls_cert_file=relayhost.example.org.crt.pem
  -o smtpd_tls_key_file=relayhost.example.org.key.pem
  -o relay_clientcerts=hash:/etc/postfix/relay_clientcerts
  -o smtpd_client_restrictions=
  -o smtpd_helo_restrictions=
  -o smtpd_sender_restrictions=
  -o smtpd_relay_restrictions=permit_tls_clientcerts,reject
  -o smtpd_recipient_restrictions=
  -o smtpd_data_restrictions=
  -o smtpd_reject_unlisted_recipient=no
```
* `/etc/postfix/relay_clientcerts`:

```
## fingerprint of mailhost.example.org.crt.pem
2A:60:75:A6:5D:67:D3:08:DF:A6:29:AE:82:71:22:18 mailhost.example.org
```

To generate such a complex setup requires time though and is error
prone. This Makefile solves both problems; with one simple command
(`make`) it generates all proper keys and presents you with
copy-n-paste instructions to configure your mail Postfix servers
and to rsync the keys to them.

## Requirements

Other than `gnupg`, `openssl` and GNU `make`, no special requirements
exists. Of course `rsync` could be handy.

## Troubleshooting

1. Raise the `smtpd_tls_loglevel` on both servers to `2`:
2. Add the `-v` (verbose) argument to the `smtpd` command in `master.cf` on the smtpd server:
```
2500      inet  n       -       n       -       -       smtpd -v
```
3. Of course perform a `postfix reload` afterwards to make postfix aware from the changes.
4. Tail both log files using `tail -f /var/log/mail.log`.


## Reference

* from http://www.postfix.org/postconf.5.html#smtpd_tls_cert_file (or man postconf):

To enable a remote SMTP client to verify the Postfix SMTP server
certificate, the issuing CA certificates must be made available to the
client. You should include the required certificates in the server
certificate file, the server certificate first, then the issuing CA(s)
(bottom-up order). Example: the certificate for "server.example.com"
was issued by "intermediate CA" which itself has a certificate of
"root CA". Create the (fullchain) server.pem file with:
```
cat server_cert.pem intermediate_CA.pem root_CA.pem > server.pem
```

If you also want to verify client certificates issued by these CAs,
you can add the CA certificates to the `smtpd_tls_CAfile`, in which case
it is not necessary to have them in the `smtpd_tls_cert_file` or
`smtpd_tls_dcert_file`.

A certificate supplied here must be usable as an SSL server
certificate and hence pass the `openssl verify -purpose sslserver ...` test.

 *NOTE*: This script uses the `smtpd_tls_CAfile` so no fullchain
         server certificate is required.

### `smtpd_tls_security_level` (default: empty)
 
The SMTP TLS security level for the Postfix SMTP server; when a
non-empty value is specified, this overrides the obsolete parameters
`smtpd_use_tls' and `smtpd_enforce_tls'. This parameter is ignored
with "smtpd_tls_wrappermode = yes".  Specify one of the following
security levels:

* `none`:    TLS will not be used.
* `may`:     Opportunistic TLS: announce STARTTLS support to remote
             SMTP clients, but do not require that clients use TLS
             encryption.
* `encrypt`: Mandatory TLS encryption: announce STARTTLS support to
             remote SMTP clients, and require that clients use TLS
             encryption. According to RFC 2487 this MUST NOT be
             applied in case of a publicly-referenced SMTP
             server. Instead, this option should be used only on
             dedicated servers.

* Note 1:    The `fingerprint`, `verify` and `secure` levels are not
             supported here. The Postfix SMTP server logs a warning
             and uses `encrypt` instead. To verify remote SMTP client
             certificates, see `TLS_README` for a discussion of the
             `smtpd_tls_ask_ccert`, `smtpd_tls_req_ccert`, and
             `permit_tls_clientcerts` features.
* Note 2:    The parameter setting `smtpd_tls_security_level = encrypt`
             implies `smtpd_tls_auth_only = yes`.
* Note 3:    When invoked via `sendmail -bs`, Postfix will never offer
             STARTTLS due to insufficient privileges to access the
             server private key. This is intended behavior.
			  
This feature is available in Postfix 2.3 and later.

### `smtpd_tls_loglevel`

 * `0`:  Disable logging of TLS activity.
 * `1`:  Log only a summary message on TLS handshake completion -- no logging of client certificate trust-chain verification errors if client certificate verification is not required.
 * `2`: Also log levels during TLS negotiation.
