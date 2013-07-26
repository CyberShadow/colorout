module colorout;

import std.c.windows.windows;
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
		"Usage: " ~ args[0] ~ " RULES.col PROGRAM [ARGS...]");
	
	int lines = int.max;
	getopt(args,
		config.stopOnFirstNonOption,
		"maxlines", &lines);

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
			rules ~= Rule(parse!(ushort)(segs[0], 16), regex(segs[1]));
		}

	auto p = pipe();
	auto pid = spawnProcess(args[2..$], stdin, p.writeEnd, p.writeEnd);
	scope(failure) wait(pid);

	auto h = GetStdHandle(STD_OUTPUT_HANDLE);

	foreach (line; p.readEnd.byLine())
	{
		lines--;
		if (lines >= 0)
		{
			ushort attr = 7;
			foreach (ref rule; rules)
				if (!match(line, rule.r).empty)
				{
					attr = rule.attr;
					break;
				}
			SetConsoleTextAttribute(h, attr);
			stderr.writeln(line);
			SetConsoleTextAttribute(h, 7);
		}
	}
	if (lines < 0)
		writefln("( ... %d lines omitted ... )", -lines);

	return wait(pid);
}
