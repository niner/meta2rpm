use common::sense;
use Cwd;
use File::Find::Rule;
use File::Slurper qw(write_text);
use Getopt::Long;

=head1 NAME

    osc package uploader script.

=head1 DESCRIPTION

    Commits packages downloaded with meta2rpm
    semi automatically into your osc project.

=head2 Usage

    1. Use meta2rpm to download all the desired modules.
    2. Copy the modules into your local osc project folder.
    3. Change directory into your local osc project folder.
    4. Run this script.

=cut

__PACKAGE__->main( @ARGV ) unless caller();

sub parse_options {
    my ($project, $usage);

    GetOptions(
        "project=s"  => \$project,
        "usage|help" => \$usage,
    );

    if ($usage) {
        say "Run this script from within your local osc project folder.\n"
            . "with parameter --project=PROJECT_NAME";
        exit;
    }

    die 'No project was specified. Please use the --usage flag.'
        if !$project;

    return $project;
}

sub main {
    my $project     = parse_options;

    my @directories = File::Find::Rule
        ->directory
        ->maxdepth(1)
        ->name('perl6*')
        ->in('.');

    system "osc up";
    for my $name (@directories) {
        next if -d "$name/.osc";

        my $title = $name;
        $title    =~ s/perl6-//;
        $title    =~ s/-/::/;

        my $spec = (glob "$name/*.spec")[0];
        open my $specfh, '<', $spec;
        my $summary;
        while (<$specfh>) {
            last if ($summary) = /^Summary:\s+(.+)$/xm;
        }
        close $specfh;

        my $meta_file = "<package name='$name'>\n"
            . "    <title>$title</title>\n"
            . "    <description>$summary</description>\n"
            . "</package>";

        write_text("$name/meta", $meta_file);

        system  "osc meta pkg -e $project $name -F $name/meta";
        unlink "$name/meta";
        system "osc co $project $name -M -c";
        system "osc remove $name/_meta";
        unlink "$name/_meta";
        system "osc add $name/*";
        chdir  $name;
        system "osc commit -m 'Adding $name'";
        chdir  "../"

    }
}

