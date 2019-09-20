=begin pod

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

=end pod

sub MAIN(Str :$project!) {

    my @dirs = dir($*CWD.IO, test => /:i ^perl6 /);

    shell "osc up";
    for @dirs -> $path {
        my $name = $path.basename;
        next if "$name/.osc".IO.d;

        my $title = $name;
        $title    ~~ s/perl6 '-'//;
        $title    ~~ s:g/'-'/::/;

        my $meta_file = "<package name='$name'>\n"
            ~ "    <title>$title\</title\>\n"
            ~ "    <description></description>\n"
            ~ '</package>';

        spurt "$name/meta", $meta_file;

        shell  "osc meta pkg -e $project $name -F $name/meta";
        unlink "$name/meta";
        shell "osc co $project $name -M -c";
        shell "osc remove $name/_meta";
        unlink "$name/_meta";
        shell "osc add $name/*";
        chdir  $name;
        shell "osc commit -m 'Adding $name'";
        chdir  "../"
    }
}

sub USAGE() {
    say "Run this script from within your local osc project folder.\n"
        ~ "with parameter --project=PROJECT_NAME";
}
