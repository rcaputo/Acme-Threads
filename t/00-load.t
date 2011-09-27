use threads; 

use Test::More tests => 2;

BEGIN {
    use_ok('Acme::Threads::Proxy');
    use_ok( 'Acme::Threads' );
}

diag( "Testing MediaWiki::DumpFile $Acme::Threads::VERSION, Perl $], $^X" );
