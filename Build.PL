use Module::Build; 

my %options = (
	module_name => 'Acme::Threads',
	dist_abstract => 'Rocket powered threads enhanced with slingshot powered object sharing',
	license     => 'perl',
	requires    => { 
		'Test::More' => '0.98',
	},
);

my $build = Module::Build->new(%options); 

$build->create_build_script;
