use strict;
use warnings;
use Test::More tests => 7;
use Test::Exception;
use Test::Deep;
use File::Temp qw( tempdir );
use Perl6::Slurp;
use JSON;
use Archive::Extract;
use File::Spec::Functions qw( splitdir catdir);

use t::autoqc_util qw( write_samtools_script );

my $tempdir = tempdir(CLEANUP => 1);

use_ok ('npg_qc::autoqc::results::bam_flagstats');
use_ok ('npg_qc::autoqc::checks::bam_flagstats');

subtest 'test attributes and simple methods' => sub {
  plan tests => 5;

  my $c = npg_qc::autoqc::checks::bam_flagstats->new(
            position => 5,
            id_run   => 4783);
  isa_ok ($c, 'npg_qc::autoqc::checks::bam_flagstats');
  is($c->subset, undef, 'subset field is not set');

  $c = npg_qc::autoqc::checks::bam_flagstats->new(
            position => 5,
            id_run   => 4783,
            subset => 'phix');
  is ($c->subset, 'phix', 'subset attr is set correctly');
  my $json = $c->result()->freeze();
  like ($json, qr/\"subset\":\"phix\"/, 'subset field is serialized');
  like ($json, qr/\"human_split\":\"phix\"/, 'human_split field is serialized');
};

subtest 'high-level parsing' => sub {
  plan tests => 10;

  my $dups  = 't/data/autoqc/bam_flagstats/4783_5_metrics_optical.txt';
  my $fstat = 't/data/autoqc/bam_flagstats/4783_5.flagstat';

  my $c = npg_qc::autoqc::checks::bam_flagstats->new(
                        id_run                 => 4783,
                        position               => 5,
                        markdups_metrics_file  => $dups,
                        flagstats_metrics_file => $fstat,
                        related_results        => []
                       );

  my $expected = from_json(
    slurp q{t/data/autoqc/bam_flagstats/4783_5_bam_flagstats.json}, {chomp=>1});

  lives_ok { $c->execute() } 'execute method is ok';
  my $r;
  my $result_json;
  lives_ok {
    $r = $c->result();
    $result_json = $r->freeze();
    $r->store(qq{$tempdir/4783_5_bam_flagstats.json});
  } 'no error when serializing to json string and file';

  my $from_json_hash = from_json($result_json);
  delete $from_json_hash->{'__CLASS__'};
  delete $from_json_hash->{'composition'};
  delete $from_json_hash->{'info'}->{'Check'};
  delete $from_json_hash->{'info'}->{'Check_version'};
   
  is_deeply($from_json_hash, $expected, 'correct json output');
  is($r->total_reads(), 32737230 , 'total reads');
  is($r->total_mapped_reads(), '30992462', 'total mapped reads');
  is($r->percent_mapped_reads, 94.6703859795102, 'percent mapped reads');
  is($r->percent_duplicate_reads, 15.6023713120952, 'percent duplicate reads');
  is($r->percent_properly_paired ,89.7229484595978, 'percent properly paired');
  is($r->percent_singletons, 2.92540938863795, 'percent singletons');
  is($r->read_pairs_examined(), 15017382, 'read_pairs_examined');
};

my $archive_16960 = '16960_1_0';
my $ae_16960 = Archive::Extract->new(archive => "t/data/autoqc/bam_flagstats/${archive_16960}.tar.gz");
$ae_16960->extract(to => $tempdir) or die $ae_16960->error;
$archive_16960 = join q[/], $tempdir, $archive_16960;
#note `find $archive_16960`;

my $samtools_path  = join q[/], $tempdir, 'samtools1';
local $ENV{'PATH'} = join q[:], $tempdir, $ENV{'PATH'};
write_samtools_script($samtools_path);

subtest 'finding files, calculating metrics' => sub {
  plan tests => 40;

  my $fproot = $archive_16960 . '/16960_1#0';
  my $r1 = npg_qc::autoqc::checks::bam_flagstats->new(
    id_run              => 16960,
    position            => 1,
    tag_index           => 0,
    input_files         => [$fproot . '.bam'],
    related_results     => [],
  );
  my $r2 = npg_qc::autoqc::checks::bam_flagstats->new(
    input_files      => [$fproot . '.bam'],
    rpt_list         => '16960:1:0',
    related_results  => [],
  );

  my $r3 = npg_qc::autoqc::checks::bam_flagstats->new(
    input_files      => [$fproot . '.bam'],
    rpt_list         => '16960:1:0;16960:2:0',
    related_results  => [],
  );

  for my $r (($r1, $r2, $r3)) {
    is($r->_file_path_root, $fproot, 'file path root');
    is($r->markdups_metrics_file,  $fproot . '.markdups_metrics.txt',
        'markdups metrics found');
    is($r->flagstats_metrics_file, $fproot . '.flagstat', 'flagstats metrics found');

    my @stats_files = sort ($fproot . '_F0x900.stats', $fproot . '_F0xB00.stats');
    is (join(q[ ], @{$r->samtools_stats_file}), join(q[ ],@stats_files), 'stats files');
 
    $r->execute();
    is($r->result()->library_size, 240428087, 'library size value');
    is($r->result()->mate_mapped_defferent_chr, 8333632, 'mate_mapped_defferent_chr value');
    my $j;
    lives_ok { $j = $r->result()->freeze } 'serialization to json is ok';
    like($j, qr/npg_tracking::glossary::composition/,
        'serialized object contains composition info');
    like($j, qr/npg_tracking::glossary::composition::component::illumina/,
        'serialized object contains component info');
    my $tmp = npg_qc::autoqc::results::bam_flagstats->thaw($j);
    isa_ok ($tmp, 'npg_qc::autoqc::results::bam_flagstats');
    isa_ok ($tmp->composition, 'npg_tracking::glossary::composition');
    isa_ok ($tmp->composition->get_component(0),
        'npg_tracking::glossary::composition::component::illumina');
    is ($r->composition->num_components, $tmp->composition->num_components,
        'number of components is consistent');
  }

  my $r = npg_qc::autoqc::checks::bam_flagstats->new(
    id_run              => 16960,
    position            => 1,
    tag_index           => 0,
    input_files         => [$fproot . '.bam'],
  );
  my $bam_md5 = join q[.], $r->_sequence_file, 'md5';
  throws_ok {$r->execute} qr{Can't open '$bam_md5'},
    'error calling execute() on related objects';
};

subtest 'finding phix subset files' => sub {
  plan tests => 10;

  my $fproot = $archive_16960 . '/16960_1#0_phix';

  my $r = npg_qc::autoqc::checks::bam_flagstats->new(
    input_files         => [$fproot . '.bam'],
    related_results     => [],
    rpt_list            => '16960:1:0',
    subset              => 'phix',
  );
  is ($r->composition->get_component(0)->subset(), 'phix',
    'subset is set for the composition');
  lives_ok {$r->execute} 'metrics parsing ok';
  is($r->result()->composition_subset, 'phix', 'subset is set for the composition');
  is($r->result()->library_size, 691461, 'library size value');
  is($r->result()->mate_mapped_defferent_chr, 0, 'mate_mapped_defferent_chr value');

  is($r->_file_path_root, $fproot, 'file path root');  
  is($r->markdups_metrics_file, $fproot . '.markdups_metrics.txt',
    'phix markdups metrics found');
  is($r->flagstats_metrics_file, $fproot . '.flagstat',
    'phix flagstats metrics found');

  my @stats_files = sort ($fproot . '_F0x900.stats', $fproot . '_F0xB00.stats');
  is (join(q[ ], @{$r->samtools_stats_file}), join(q[ ],@stats_files), 'phix stats files');
  lives_ok { $r->result()->freeze } 'no run id - serialization to json is ok';
};

my $archive = '17448_1_9';
my $ae = Archive::Extract->new(archive => "t/data/autoqc/bam_flagstats/${archive}.tar.gz");
$ae->extract(to => $tempdir) or die $ae->error;
$archive = join q[/], $tempdir, $archive;
my $qc_dir = join q[/], $archive, 'testqc';
note `find $archive`;
write_samtools_script($samtools_path, join(q[/], $archive, 'cram.header'));

subtest 'full functionality with full file sets' => sub {
  plan tests => 76;

  mkdir $qc_dir;

  my $fproot_common = $archive . '/17448_1#9';
  my $composition_digest = 'bfc10d33f4518996db01d1b70ebc17d986684d2e04e20ab072b8b9e51ae73dfa';
  my @filters = qw/F0x900 F0xB00/;

  foreach my $subset ( qw(default phix) ) {
    foreach my $file_type ( qw(cram bam) ) {

      my $local_qc_dir = join q[/], $qc_dir, $file_type;
      if (!-e $local_qc_dir) {
        mkdir $local_qc_dir;
      }

      my $ref = {
        id_run        => 17448,
        position      => 1,
        tag_index     => 9,
        qc_out        => $local_qc_dir,
                };
      my $fproot = $fproot_common;
      if ($subset eq 'phix') {
        $fproot .= q[_] . $subset;
        $ref->{'subset'} = $subset;
        $composition_digest = 'ca4c3f9e6f8247fed589e629098d4243244ecd71f588a5e230c3353f5477c5cb';
      }

      my $sfile = join q[.], $fproot, $file_type;
      $ref->{'input_files'} = [$sfile];
     
      my $r = npg_qc::autoqc::checks::bam_flagstats->new($ref);
      lives_ok { $r->run() } 'no error calling run()';

      my @ros = @{$r->related_results};
      is (scalar @ros, 3, 'three related results');

      my $i = 0;
      while ($i < 2) {
        my $ro = $ros[$i];
        my $filter = $filters[$i];
        isa_ok ($ro, 'npg_qc::autoqc::results::samtools_stats');
        is ($ro->filter, $filter, 'correct filter');
        is ($ro->stats_file, $fproot . q[_] . $filter . '.stats', 'stats file path');
        isa_ok ($ro->composition, 'npg_tracking::glossary::composition');
        is ($ro->composition_digest, $composition_digest, 'composition digest');
        $i++;
      }

      my $ro = $ros[2];
      isa_ok ($ro, 'npg_qc::autoqc::results::sequence_summary');
      isa_ok ($ro->composition, 'npg_tracking::glossary::composition');
      is ($ro->composition_digest, $composition_digest, 'composition digest');

      foreach my $output_type ( qw(.bam_flagstats.json
                                   .sequence_summary.json
                                   _F0xB00.samtools_stats.json
                                   _F0x900.samtools_stats.json) ) {
        my @dirs = splitdir $fproot;
        my $name = pop @dirs;
        my $output = catdir($local_qc_dir, $name) . $output_type;
        ok (-e $output, "output $output created");
      }
    }
  }
};

1;
