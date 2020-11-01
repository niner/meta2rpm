use Test;
use lib 'lib';
use JSON::Fast;
use File::Temp;

use RpmSpecMaker;

plan 21;

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

lives-ok {generate-spec($valid-json)}, "No exception for valid json string and crated package directory";
my $meta = from-json($valid-json);

dies-ok { generate-spec(:$meta, "doesnotexists".IO) }, "Dies without created package directory";
is get-name($meta), "perl6-IO-Prompt", "Name found";
is provides(meta => from-json($valid-json)), "Provides:       perl6(IO::Prompt)", "Provides returns proper string";

is requires(:$meta), "Requires:       perl6 >= 2016.12", "Requires returns one dependency";
is requires( meta => { depends => ["Method::Also"] }), chomp(q:to/SPEC/), "Requires returns several dependencies";
    Requires:       perl6 >= 2016.12
    Requires:       perl6(Method::Also)
    SPEC
is requires( meta => { depends => { runtime => { "requires" => ["Cairo","Color"] } } }), chomp(q:to/SPEC/), "Requires returns several runtime dependencies";
    Requires:       perl6 >= 2016.12
    Requires:       perl6(Cairo)
    Requires:       perl6(Color)
    SPEC

is build-requires(:$meta), "BuildRequires:  rakudo >= 2017.04.2", "Build-requires returns one dependency";
is build-requires(meta => {build-depends =>  ["LibraryMake","Pod::To::Markdown"] } ), chomp(q:to/SPEC/), "Build-requires returns several dependency";
    BuildRequires:  rakudo >= 2017.04.2
    BuildRequires:  perl6(LibraryMake)
    BuildRequires:  perl6(Pod::To::Markdown)
    SPEC
is build-requires(meta => {build-depends =>  ["LibraryMake"], depends => { build => { "requires" => ["Pod::To::Markdown"]}} } ), chomp(q:to/SPEC/), "Build-requires returns also depends dependency";
    BuildRequires:  rakudo >= 2017.04.2
    BuildRequires:  perl6(Pod::To::Markdown)
    BuildRequires:  perl6(LibraryMake)
    SPEC

my $package-dir = tempdir().IO;
my $spec = generate-spec(:$meta, :$package-dir);

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
