package Acme::Threads; 

our $VERSION = '0.0.0_00';

use strict;
use warnings; 
use threads;
use threads::shared; 
use Thread::Queue; 
use Data::Dumper; 
use Time::HiRes qw (setitimer); 

use Acme::Threads::Proxy;

our %threadIdToRPCBuffer : shared; 
my %threadHeap;

sub create {
	my ($class, $entry, @args) = @_; 
	my $queue = Thread::Queue->new; 
	my $threadIsReady : shared; 
	my ($proxy, $thread);
		
	$thread = threads->create(sub {
		$class->init_new_thread; 			
		$class->set_rpc_buffer($queue); 
		
		{
			lock($threadIsReady); 
			$threadIsReady = 1; 
			cond_signal($threadIsReady); 
		}
				
		return $entry->(@args);	
	});
			
	lock($threadIsReady); 
	
	while(1) {
		last if defined $threadIsReady; 
		cond_wait($threadIsReady);
	}
	
	return $thread;
}

sub spawn {
	my ($ourClass, $wantedClass, $constructor, @args) = @_;
	my $thread;
	my %stash : shared; 
		
	$thread = Acme::Threads->create(sub {
		my $self = $wantedClass->$constructor(@args); 
		
		{
			lock(%stash);
						
			$stash{proxy} = Acme::Threads->proxy_for_object($self); 
			cond_signal(%stash); 
		}	

		#there's got to be something better to block on to hold the thread open		
		while(1) { sleep(.001); }		
	});
	
	lock(%stash);

	while(1) {
		last if defined $stash{proxy};
		cond_wait(%stash);
	}	
		
	return $stash{proxy}; 	
}

sub init_new_thread {
	my ($class) = @_;
	
	$SIG{HUP} = sub { $class->check_rpc_buffer };
	
	$class->init_thread_globals;
}

sub init_thread_globals {
	my ($class) = @_;
	
	undef(%threadHeap); 	
}

sub set_rpc_buffer {
	my ($class, $buffer) = @_;
	
	$threadIdToRPCBuffer{threads->tid} = $buffer; 
}

sub check_rpc_buffer {
	my ($class) = @_;
	my $queue = $threadIdToRPCBuffer{threads->tid};
	my @items; 

	while(my $rpcInvocation = $queue->dequeue_nb) {
		$class->process_rpc_request($rpcInvocation); 
	}		
}

sub process_rpc_request {
	my ($class, $request) = @_; 

	lock(%$request); 
	
	if (defined($request->{method})) {
		return $class->rpc_method_invocation($request); 
	} elsif (defined($request->{release})) {
		die "attempt to free reference that does not exist" unless delete $threadHeap{objectRefs}->{$request->{refNumber}};
	}		
}

sub rpc_method_invocation {
	my ($class, $request) = @_; 
	my @return; 

	eval {
		my $method = $request->{method}; 
		my $object = $threadHeap{objectRefs}->{$request->{refNumber}}; 
		
		unless(defined $object) {
			print Dumper(\%threadHeap);
			die "could not get original object for reference number ", $request->{refNumber}; 
		}
				
		unless (defined($request->{context})) {
			$object->$method(@{$request->{args}});
		} elsif ($request->{context}) {
			@return = $object->$method(@{$request->{args}});	
		} else {
			@return = scalar($object->$method(@{$request->{args}}));
		}
	};

	if ($@) {
		$request->{die} = $@; 
	} else {
		$request->{return} = $class->proxy_unshareable(@return);
	}
	
	cond_signal(%$request); 
	
}

sub proxy_unshareable {
	my ($class, @returned) = @_; 
		
	for(my $i = 0; $i <= $#returned; $i++) {
		my $refType = ref($returned[$i]); 

		next if $refType eq '' || $refType eq 'HASH' || $refType eq 'ARRAY' || $refType eq 'SCALAR'; 

		$returned[$i] = $class->proxy_for_object($returned[$i]);
	}
	
	return shared_clone(\@returned); 
}

sub proxy_for_object {
	my ($class, $object) = @_; 
	my $refNumber = ++$threadHeap{refCounter};	
				
	$threadHeap{objectRefs}{$refNumber} = $object; 
	
	return Acme::Threads::Proxy->new($refNumber); 
}

sub rpc_buffer {
	my ($class) = @_;
	
	return $threadIdToRPCBuffer{threads->tid}; 
}

1; 