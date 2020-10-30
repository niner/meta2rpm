use Test;
use lib 'lib';
use JSON::Fast;

use RpmSpecMaker;

rm-directories("packages".IO);


plan 22;

dies-ok { generate-spec('No valid json') }, "Invalid json dies";

my $valid-json = q:to/END/;
        {
   "authors" : [
      "pnu",
      "wbiker"
   ],
   "build-depends" : [],
   "depends" : [],
   "description" : "This is a generic module for interactive prompting from the console.",
   "license" : "Artistic-2.0",
   "name" : "IO::Prompt",
   "perl" : "6.*",
   "provides" : {
      "IO::Prompt" : "lib/IO/Prompt.pm"
   },
   "resources" : [],
   "source-url" : "http://www.cpan.org/authors/id/W/WB/WBIKER/Perl6/IO-Prompt-0.0.2.tar.gz",
   "tags" : [],
   "test-depends" : [
      "Test"
   ],
   "version" : "0.0.2"
}
END

dies-ok { generate-spec($valid-json) }, "Dies without created package directory";

is get-directory("perl6-IO-Prompt"), "packages/perl6-IO-Prompt", "Package directory found";
get-directory("perl6-IO-Prompt").mkdir;

lives-ok {generate-spec($valid-json)}, "No exception for valid json string and crated package directory";
my $meta = from-json($valid-json);

is get-name($meta), "perl6-IO-Prompt", "Name found";
is provides(meta => from-json($valid-json)), "Provides:       perl6(IO::Prompt)", "Provides returns proper string";

is requires(:$meta), "Requires:       perl6 >= 2016.12", "Requires returns one dependency";
is requires( meta => { depends => ["Method::Also"] }),
    "Requires:       perl6 >= 2016.12\nRequires:       perl6(Method::Also)",
    "Requires returns several dependencies";
is requires( meta => { depends => { runtime => { "requires" => ["Cairo","Color"] } } }),
    "Requires:       perl6 >= 2016.12\nRequires:       perl6(Cairo)\nRequires:       perl6(Color)",
    "Requires returns several runtime dependencies";

is build-requires(:$meta), "BuildRequires:  rakudo >= 2017.04.2", "Build-requires returns one dependency";
is build-requires(meta => {build-depends =>  ["LibraryMake","Pod::To::Markdown"] } ),
    "BuildRequires:  rakudo >= 2017.04.2\nBuildRequires:  perl6(LibraryMake)\nBuildRequires:  perl6(Pod::To::Markdown)",
    "Build-requires returns several dependency";
is build-requires(meta => {build-depends =>  ["LibraryMake"], depends => { build => { "requires" => ["Pod::To::Markdown"]}} } ),
    "BuildRequires:  rakudo >= 2017.04.2\nBuildRequires:  perl6(Pod::To::Markdown)\nBuildRequires:  perl6(LibraryMake)",
    "Build-requires returns also depends dependency";

my $spec = generate-spec($meta);

like $spec, /'Source:         perl6-IO-Prompt-0.0.2.tar.xz'/, "Source found in spec file";
like $spec, /'Name:           perl6-IO-Prompt'/, "Name found in spec file";
like $spec, /'Version:        0.0.2'/, "Version found in spec file";
like $spec, /'Release:        1.1'/, "Release found in spec file";
like $spec, /'License:        Artistic-2.0'/, "License found in spec file";
like $spec, /'BuildRequires:  fdupes'/, "BuildRequires found in spec file";
like $spec, /'BuildRequires:  fdupes' \n 'BuildRequires:  rakudo >= 2017.04.2'/, "BuildRequires found in spec file";
like $spec, /'Requires:       perl6 >= 2016.12'/, "Requires found in spec file";
like $spec, /'Provides:       perl6(IO::Prompt)'/, "Provides found in spec file";
like $spec, /'BuildRoot:      %{_tmppath}/%{name}-%{version}-build'/, "BuildRoot found in spec file";

sub rm-directories(IO::Path $dir) {
    return unless $dir.e;

    for $dir.dir -> $item {
        rm-directories($item) if $item.d;

        $item.unlink;
    }
    $dir.rmdir;
}