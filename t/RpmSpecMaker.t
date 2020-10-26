use Test;
use lib 'lib';
use JSON::Fast;

use RpmSpecMaker;

subtest {
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
    is requires(:$meta), "Requires:       perl6 >= 2016.12", "Requires returns proper string";
    is build-requires(:$meta), "BuildRequires:  rakudo >= 2017.04.2", "Build-requires returns proper string";

    my $spec = generate-spec($meta);


    done-testing
}

done-testing;
