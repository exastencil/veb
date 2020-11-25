module main

import os
import strings
import net.openssl
import net.urllib { URL }
import term
import term.ui

const (
	bufsize = 1536
)

struct Request {
	url URL
}

struct Response {
	status string
	meta   string
	body   []string
}

struct Browser {
mut:
	ui       &ui.Context = 0
	width    int = 80
	height   int = 60
	response Response
}

fn main() {
	mut interactive := false
	for arg in os.args {
		if arg == '-i' {
			interactive = true
		}
	}
	if interactive {
		terminal()
	} else {
		cli()
	}
}

fn event(e &ui.Event, x voidptr) {
	// mut browser := &Browser(x)
	// Quit
	if e.typ == .key_down && e.code == .q {
		exit(0)
	}
}

fn frame(x voidptr) {
	mut browser := &Browser(x)
	// browser.ui.clear()
	browser.ui.draw_text(0, 0, '$browser.response.status $browser.response.meta')
	match browser.response.status {
		'20' {
			for ix, line in browser.response.body {
				browser.ui.draw_text(0, ix + 1, line)
			}
		}
		else {
			browser.ui.draw_text(4, 0, browser.response.meta)
		}
	}
	// browser.ui.reset()
	browser.ui.flush()
}

// Default or requested location
fn build_initial_location() URL {
	mut input := 'gemini.circumlunar.space'
	if os.args.len > 1 {
		input = os.args[1]
	}
	url := process_destination(input)
	return url
}

// Load starting URL
fn landing() Response {
	mut url := build_initial_location()
	request := Request{url: url}
	mut response := request.do()
	if response.status.starts_with('3') {
		url = process_destination(response.meta)
		redirect := Request{url: url}
		response = redirect.do()
	}
	return response
}

// Interactive mode
fn terminal() {
	width, height := term.get_terminal_size()
	mut browser := &Browser{}
	browser.width = width
	browser.height = height
	browser.response = landing()
	browser.ui = ui.init(
		user_data: browser
		event_fn: event
		frame_fn: frame
		hide_cursor: true
	)
	browser.ui.clear()
	browser.ui.reset()
	browser.ui.run()
}

// Command Line Interface
fn cli() {
	response := landing()
	if response.status.starts_with('2') {
		println(response.body.join('\r\n'))
	} else {
		println('$response.status $response.meta')
	}
}

// Takes in a user-familiar string and outputs a URI
fn process_destination(dest string) URL {
	mut input := dest
	// Default scheme is `gemini`
	if !dest.starts_with('gemini://') {
		input = 'gemini://$input'
	}
	mut url := urllib.parse(input) or {
		panic("Invalid target destination: $input")
	}
	// Default port
	if !url.host.ends_with(':1965') {
		url.host = '$url.host:1965'
	}
	return url
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

// Process received text into a reponse
fn (req Request) do() Response {
	result := fetch(req.url) or { '50 Could not reach server\r\n' }
	lines := result.split_into_lines()
	status := lines[0].substr(0, 2)
	meta := lines[0].substr(2, lines[0].len).trim_space()
	if lines.len > 1 {
		// Repsponse with body
		return Response{
			status: status
			meta: meta
			body: lines.slice(1, lines.len)
		}
	} else {
		// Header only reponse
		return Response{
			status: status
			meta: meta
		}
	}
}
