module gemini

// Line represents a line of a Gemini text response
interface Line {
	str() string
}

// A line with a link
struct LineLink {
	url         string
	description string
}

pub fn (l LineLink) str() string {
	if l.description != '' {
		return '=> $l.url $l.description'
	}
	return '=> $l.url'
}

// A preformatting toggle line
type LinePreformattingToggle = string

pub fn (l LinePreformattingToggle) str() string {
	return '```$l'
}

// A preformatted text line
type LinePreformattedText = string

pub fn (l LinePreformattedText) str() string {
	return '$l'
}

// A first-level heading line
type LineHeading1 = string

fn (l LineHeading1) str() string {
	return '# $l'
}

// A second-level heading line
type LineHeading2 = string

pub fn (l LineHeading2) str() string {
	return '## $l'
}

// A third-level heading line
type LineHeading3 = string

pub fn (l LineHeading3) str() string {
	return '### $l'
}

// An unordered list item line
type LineListItem = string

pub fn (l LineListItem) str() string {
	return '* $l'
}

// A quote line
type LineQuote = string

pub fn (l LineQuote) str() string {
	return '> $l'
}

// A text line
type LineText = string

pub fn (l LineText) str() string {
	return '$l'
}

// Text represents a text/gemini document
type Text = []Line

// parse_text parses a Gemini text from an io.Reader
pub fn parse_text(s string) Text {
	lines := s.split_into_lines()
	mut text := []Line
	whitespace := ' \t'
	mut pre := false
	for line in lines {
		if line.starts_with('```') {
			pre = !pre
			text << LinePreformattingToggle(line[3:])
		} else if pre {
			text << LinePreformattedText(line)
		} else if line.starts_with('=>') {
			content := line[2:].trim_left(whitespace)
			split := content.index_any(whitespace)
			if split == -1 {
				// URL only
				text << LineLink{url: content}
			} else {
				// URL and description
				url := text[:split]
				description := text[split:].trim_space()
				text << LineLink{url: url, description: description}
			}
		} else if line.starts_with('*') {
			text << LineListItem(line[1:].trim_space())
		} else if line.starts_with('###') {
			text << LineHeading3(line[3:].trim_space())
		} else if line.starts_with('##') {
			text << LineHeading2(line[2:].trim_space())
		} else if line.starts_with('#') {
			text << LineHeading1(line[1:].trim_space())
		} else if line.starts_with('>') {
			text << LineQuote(line[1:].trim_space())
		} else {
			text << LineText(line)
		}
	}
	return text
}
