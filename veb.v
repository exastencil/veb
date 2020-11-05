module main

import strings
import net.openssl
import net.urllib { URL }

const (
	bufsize = 1536
)

struct Request {
	host_name string
	port      int
	path      string
	query     string
}

fn main() {
	mut url := urllib.parse('gemini://gemini.circumlunar.space/') ?
	// Default port
	if !url.host.ends_with(':1965') {
		url.host = '$url.host:1965'
	}
	// Default scheme
	if url.scheme == '' {
		url.scheme = 'gemini'
	}
	response := fetch(url) ?
	println(response)
}

fn fetch(url URL) ?string {
	ssl_method := C.TLSv1_2_method()
	ctx := C.SSL_CTX_new(ssl_method)
	C.SSL_CTX_set_verify_depth(ctx, 4)
	flags := C.SSL_OP_NO_SSLv2 | C.SSL_OP_NO_SSLv3 | C.SSL_OP_NO_COMPRESSION
	C.SSL_CTX_set_options(ctx, flags)
	mut res := C.SSL_CTX_load_verify_locations(ctx, 'random-org-chain.pem', 0)
	web := C.BIO_new_ssl_connect(ctx)
	res = C.BIO_set_conn_hostname(web, url.host.str)
	ssl := &openssl.SSL(0)
	C.BIO_get_ssl(web, &ssl)
	preferred_ciphers := 'HIGH:!aNULL:!kRSA:!PSK:!SRP:!MD5:!RC4'
	res = C.SSL_set_cipher_list(ssl, preferred_ciphers.str)
	if res != 1 {
		println('veb: openssl: cipher failed')
	}
	res = C.SSL_set_tlsext_host_name(ssl, url.host.str)
	res = C.BIO_do_connect(web)
	if res != 1 {
		return error('cannot connect the endpoint')
	}
	res = C.BIO_do_handshake(web)
	C.SSL_get_peer_certificate(ssl)
	res = C.SSL_get_verify_result(ssl)
	req_header := '$url\r\n'
	C.BIO_puts(web, req_header.str)
	mut content := strings.new_builder(100)
	mut buff := [bufsize]byte{}
	mut readcounter := 0
	for {
		readcounter++
		len := C.BIO_read(web, buff, bufsize)
		if len <= 0 {
			break
		}
		$if debug ? {
			eprintln('do, read ${readcounter:4d} | len: $len')
			eprintln('-'.repeat(20))
			eprintln(tos(buff, len))
			eprintln('-'.repeat(20))
		}
		content.write_bytes(buff, len)
	}
	if web != 0 {
		C.BIO_free_all(web)
	}
	if ctx != 0 {
		C.SSL_CTX_free(ctx)
	}
	return content.str()
}
