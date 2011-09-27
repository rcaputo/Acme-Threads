package Acme::Threads::Proxy;

use strict;
use warnings;
use Data::Dumper; 

use threads::shared; 

our $AUTOLOAD; 

sub new {
	my ($class, $refNumber) = @_; 
	my $self = shared_clone({}); 
		
	$self->{threadId} = threads->tid; 
	$self->{rpcBuffer} = Acme::Threads->rpc_buffer; 
	$self->{refNumber} = $refNumber; 
	
	bless($self, $class);
	
	return $self; 
}

sub DESTROY {
	my ($self) = @_; 
	my %invocation : shared;

	return unless threads->tid != $self->{threadId}; 

	$invocation{release} = 1; 	
	$invocation{refNumber} = $self->{refNumber}; 
	
	Acme::Threads::Proxy::Subs::add_to_queue($self, \%invocation); 
		
	return; 
}

sub AUTOLOAD {
	my ($self, @args) = @_; 
	my $name = $AUTOLOAD; 
	my $context = wantarray; 
	my %invocation : shared;
		
	$name =~ s/.*://;   # strip fully-qualified portion
		
	$invocation{args} = Acme::Threads->proxy_unshareable(@args);
	$invocation{method} = $name;
	$invocation{context} = $context; 	
	$invocation{refNumber} = $self->{refNumber}; 
			
	Acme::Threads::Proxy::Subs::add_to_queue($self, \%invocation); 
	Acme::Threads::Proxy::Subs::wait_for_remote_side($self, \%invocation); 
		
	if (exists $invocation{die}) {
		die "method invocation died on thread ", $self->{threadId}, ": ", $invocation{die};  
	}

	#handle void context
	return unless defined $context; 
	#handle list context
	return @{$invocation{return}} if $context;
	#handle scalar context
	return $invocation{return}->[0]; 
}

package Acme::Threads::Proxy::Subs; 

use strict;
use warnings; 

use threads::shared; 
use Data::Dumper; 

sub add_to_queue {
	my ($self, $item) = @_;
	my $queue = $self->{rpcBuffer};
	my $threadId = $self->{threadId}; 
	
	$self->{rpcBuffer}->enqueue($item);
	
	my $thread = threads->object($threadId); 
			
	$thread->kill('HUP');
		
	return; 
}

sub wait_for_remote_side {
	my ($self, $invocation) = @_;
	
	lock(%$invocation); 
		
	while(1) {
		cond_wait(%$invocation);
		
		last if exists $invocation->{return};
		last if exists $invocation->{die};  
	}	
	
	return; 

}

1; 