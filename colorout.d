module colorout;

/++
	Color file syntax:

	Each line has the structure: <COLOR><TAB><REGEX>
	- <COLOR> is the console attribute to assign to
	  the line, if <REGEX> matches. Windows console
	  attributes are a superset of VGA color codes,
	  for more information see:
	  http://msdn.microsoft.com/en-us/library/windows/desktop/ms682088(v=vs.85).aspx#_win32_character_attributes
	  If <COLOR> is 0x00, only regex named groups are
	  processed, the attribute is not applied, and
	  the search continues.
	  If <COLOR> is 0x11, the line is omitted from
	  the output completely.
	- <REGEX> is a regular expression matched against
	  each output line.
	  If it contains the named groups <file> and
	  <line>, these are written to the file specified
	  using the --locations command-line parameter.
++/

import std.c.windows.windows;
import std.algorithm;
import std.conv;
import std.exception;
import std.getopt;
import std.path;
import std.process;
import std.regex : regex, Regex, match;
import std.stdio;
import std.string;

int main(string[] args)
{
	enforce(args.length >= 3,
		"Usage: " ~ args[0] ~ " RULES.col [--maxlines=N] [--locations=FILENAME] PROGRAM [ARGS...]");
	
	int lines = int.max;
	string locationsFileName;
	getopt(args,
		config.stopOnFirstNonOption,
		"maxlines", &lines,
		"locations", &locationsFileName,
	);

	struct Rule
	{
		ushort attr;
		Regex!char r;
	}
	Rule[] rules;
	foreach (line; File(buildPath(dirName(args[0]), args[1])).byLine())
		if (line.length)
		{
			auto segs = line.strip().split("\t");
			rules ~= Rule(parse!(ushort)(segs[0], 16), regex(segs[1].idup));
		}

	auto p = pipe();
	auto pid = spawnProcess(args[2..$], stdin, p.writeEnd, p.writeEnd);
	scope(failure) wait(pid);

	auto h = GetStdHandle(STD_OUTPUT_HANDLE);

	File locations;
	if (locationsFileName)
		locations.open(locationsFileName, "wb");

lineLoop:
	foreach (line; p.readEnd.byLine())
	{
		line = line.chomp();
		ushort attr = 7;
		foreach (ref rule; rules)
		{
			auto m = match(line, rule.r);
			if (m)
			{
				auto names = rule.r.namedCaptures;
				if (locationsFileName && names.canFind("file") && names.canFind("line"))
				{
					auto fields =
					[
						m.captures["file"],
						m.captures["line"],
						names.canFind("column" ) ? m.captures["column" ] : "",
						names.canFind("message") ? m.captures["message"] : line,
					];
					locations.writeln(fields.join("\t"));
				}

				if (rule.attr == 0x00)
					continue;
				else
				if (rule.attr == 0x11)
					//continue lineLoop; // https://d.puremagic.com/issues/show_bug.cgi?id=11885
					goto nextLine;
				else
				{
					attr = rule.attr;
					break;
				}
			}
		}

		lines--;
		if (lines >= 0)
		{
			SetConsoleTextAttribute(h, attr);
			stderr.writeln(line);
			SetConsoleTextAttribute(h, 7);
		}

	nextLine:
	}
	if (lines < 0)
		writefln("( ... %d lines omitted ... )", -lines);

	return wait(pid);
}
