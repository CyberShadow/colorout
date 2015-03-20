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
	  each output line. Any named groups are wrritten
	  as objects (one per line) to the file specified
	  by the --json command-line parameter.
	- If a matched rule has a named group matching
	  the NAME of a --trigger parameter, the
	  corresponding PROGRAM is ran at the end.
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

import ae.utils.json;

int main(string[] args)
{
	enforce(args.length >= 3,
		"Usage: " ~ args[0] ~ " RULES.col [--maxlines=N] [--json=FILENAME] [--trigger NAME=PROGRAM] PROGRAM [ARGS...]");
	
	int lines = int.max;
	string jsonFileName;
	string[string] triggers;
	getopt(args,
		config.stopOnFirstNonOption,
		"maxlines", &lines,
		"json", &jsonFileName,
		"trigger", (string t, string param) { triggers[param.split("=")[0]] = param.split("=")[1]; },
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

	File json;
	if (jsonFileName)
		json.open(jsonFileName, "wb");

	char[] readRawLine()
	{
		static ubyte[] buf;
		static bool isEOL(ubyte c) { return c == 13 || c == 10; }
		while (!buf.any!isEOL)
		{
			static ubyte[1] readBuf;
			uint bytesRead;
			if (!ReadFile(p.readEnd.windowsHandle, readBuf.ptr, readBuf.length, &bytesRead, null) || bytesRead==0)
				break;
			buf ~= readBuf[0..bytesRead];
		}
		auto eol = buf.countUntil!isEOL;
		if (eol < 0)
			eol = buf.length;
		while (eol < buf.length && isEOL(buf[eol]))
			eol++;
		auto result = buf[0..eol];
		buf = buf[eol..$];
		return cast(char[])result;
	}

	bool[string] matchedTriggers;

	char[] lineEOL;
	while ((lineEOL = readRawLine()).length)
	{
		auto line = lineEOL.chomp();
		ushort attr = 7;
		char[][string] namedCaptures;
		bool print = true;

		foreach (ref rule; rules)
		{
			auto m = match(line, rule.r);
			if (m)
			{
				foreach (name; rule.r.namedCaptures)
					namedCaptures[name] = m.captures[name];

				if (rule.attr == 0x00)
					continue;
				else
				if (rule.attr == 0x11)
				{
					print = false;
					break;
				}
				else
				{
					attr = rule.attr;
					break;
				}
			}
		}

		if (jsonFileName && namedCaptures)
			json.writeln(namedCaptures.toJson());

		foreach (k, v; namedCaptures)
			if (k in triggers)
				matchedTriggers[triggers[k]] = true;

		if (print)
		{
			lines--;
			if (lines >= 0)
			{
				SetConsoleTextAttribute(h, attr);
				stderr.rawWrite(lineEOL);
				SetConsoleTextAttribute(h, 7);
			}
		}
	}
	if (lines < 0)
		writefln("( ... %d lines omitted ... )", -lines);

	if (jsonFileName)
		json.close();

	auto status = wait(pid);

	foreach (program; matchedTriggers.byKey)
		spawnShell(program).wait();

	return status;
}
