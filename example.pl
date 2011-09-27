#currently hangs when put under much load 

use strict;
use warnings;

use Acme::Threads; 
use IO::File; 
use Time::HiRes qw(setitimer ITIMER_REAL);  

#unhangs the system, weird 
$SIG{ALRM} = sub { };
setitimer(ITIMER_REAL, 1, 1);

my $input = Acme::Threads->spawn('Input', 'new'); 

#this leaks objects
#while(defined(my $line = $input->fh->getline)) {
#	print $line; 
#}

#but this leaks less 
while(1) {
	my $fh = $input->fh;
	my $line = $fh->getline;
	
	print $line; 
}

package Input;

use strict;
use warnings; 

sub new {
	return bless({}, $_[0]);
}

sub fh {
	return \*STDIN; 
}