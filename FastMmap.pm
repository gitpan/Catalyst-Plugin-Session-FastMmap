package Catalyst::Plugin::Session::FastMmap;

use strict;
use base qw/Class::Data::Inheritable Class::Accessor::Fast/;
use NEXT;
use Cache::FastMmap;
use Digest::MD5;
use URI;
use URI::Find;
use File::Temp 'tempdir';

our $VERSION = '0.12';

__PACKAGE__->mk_classdata('_session');
__PACKAGE__->mk_accessors('sessionid');

=head1 NAME

Catalyst::Plugin::Session::FastMmap - FastMmap sessions for Catalyst

=head1 SYNOPSIS

    use Catalyst 'Session::FastMmap';
    
    MyApp->config->{session} = {
        expires => 3600,
        rewrite => 1,
        storage => '/tmp/session'
    };

    $c->session->{foo} = 'bar';
    print $c->sessionid;

=head1 DESCRIPTION

Fast sessions.

=head2 EXTENDED METHODS

=head3 finalize

=cut

sub finalize {
    my $c = shift;
    if ( $c->config->{session}->{rewrite} ) {
        my $redirect = $c->response->redirect;
        $c->response->redirect( $c->uri($redirect) ) if $redirect;
    }
    if ( my $sid = $c->sessionid ) {
        $c->_session->set( $sid, $c->session );
        my $set = 1;
        if ( my $cookie = $c->request->cookies->{session} ) {
            $set = 0 if $cookie->value eq $sid;
        }
        if ( $set ) {
            $c->response->cookies->{session} = { 
                value   => $sid, 
                expires => '+' . $c->config->{session}->{expires} . 's'
            };
        }
        if ( $c->config->{session}->{rewrite} ) {
            my $finder = URI::Find->new(
                sub {
                    my ( $uri, $orig ) = @_;
                    my $base = $c->request->base;
                    return $orig unless $orig =~ /^$base/;
                    return $orig if $uri->path =~ /\/-\//;
                    return $c->uri($orig);
                }
            );
            $finder->find( \$c->res->{body} ) if $c->res->body;
        }
    }
    return $c->NEXT::finalize(@_);
}

=head3 prepare_action

=cut

sub prepare_action {
    my $c = shift;
    if ( $c->request->path =~ /^(.*)\/\-\/(.+)$/ ) {
        $c->request->path($1);
        $c->sessionid($2);
        $c->log->debug(qq/Found sessionid "$2" in path/) if $c->debug;
    }
    if ( my $cookie = $c->request->cookies->{session} ) {
        my $sid = $cookie->value;
        $c->sessionid($sid);
        $c->log->debug(qq/Found sessionid "$sid" in cookie/) if $c->debug;
    }
    $c->NEXT::prepare_action(@_);
}

sub session {
    my $c = shift;
    return $c->{session} if $c->{session};
    my $sid = $c->sessionid;
    if (   $sid
        && $c->_session
        && ( $c->{session} = $c->_session->get($sid) ) )
    {
        $c->log->debug(qq/Found session "$sid"/) if $c->debug;
        return $c->{session};
    }
    else {
        my $sid = Digest::MD5::md5_hex( time, rand, $$, 'catalyst' );
        $c->sessionid($sid);
        $c->log->debug(qq/Created session "$sid"/) if $c->debug;
        return $c->{session} = {};
    }
}

=head3 setup

=cut

sub setup {
    my $self = shift;
    $self->config->{session}->{storage} ||= '/tmp/session';
    $self->config->{session}->{expires} ||= 60 * 60 * 24;
    $self->config->{session}->{rewrite} ||= 0;

    $self->_session(
        Cache::FastMmap->new(
            share_file  => $self->config->{session}->{storage},
            expire_time => $self->config->{session}->{expires}
        )
    );

    return $self->NEXT::setup(@_);
}

=head2 METHODS

=head3 session

=head3 uri

Extends an uri with session id if needed.

    my $uri = $c->uri('http://localhost/foo');

=cut

sub uri {
    my ( $c, $uri ) = @_;
    if ( my $sid = $c->sessionid ) {
        $uri = URI->new($uri);
        my $path = $uri->path;
        $path .= '/' unless $path =~ /\/$/;
        $uri->path( $path . "-/$sid" );
        return $uri->as_string;
    }
    return $uri;
}

=head2 CONFIG OPTIONS

=head3 rewrite

To enable automatic storing of sessions in the url set this to a true value.

=head3 storage

File to mmap for sharing of data, defaults to /tmp/session.

=head3 expires

how many seconds until the session expires. defaults to 1 day

=head1 SEE ALSO

L<Catalyst> L<Cache::FastMmap>.

=head1 AUTHOR

Sebastian Riedel, C<sri@cpan.org>
Marcus Ramberg C<mramberg@cpan.org>

=head1 COPYRIGHT

This program is free software, you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
