<?php
// Idempotently create the OAuth API client for the bootstrapped admin from API_CLIENT_ID / API_CLIENT_SECRET.
require '/var/www/wallabag/vendor/autoload.php';
$kernel = new AppKernel('prod', false);
$kernel->boot();
$em = $kernel->getContainer()->get('doctrine')->getManager();
$randomId = getenv('API_CLIENT_ID');
$secret = getenv('API_CLIENT_SECRET');
$username = getenv('WALLABAG_ADMIN_USER') ?: 'wallabag';
if (!$randomId || !$secret) { fwrite(STDERR, "API_CLIENT_ID and API_CLIENT_SECRET required\n"); exit(1); }
$user = $em->getRepository(Wallabag\UserBundle\Entity\User::class)->findOneBy(['username' => $username]);
if (!$user) { fwrite(STDERR, "user $username not found\n"); exit(2); }
$client = $em->getRepository(Wallabag\ApiBundle\Entity\Client::class)->findOneBy(['randomId' => $randomId]);
if (!$client) {
    $client = new Wallabag\ApiBundle\Entity\Client($user);
    $client->setName('Template API client');
    $client->setRandomId($randomId);
    $client->setAllowedGrantTypes(['password', 'refresh_token']);
    $client->setRedirectUris([]);
    $user->addClient($client);
    $em->persist($client);
}
$client->setSecret($secret);
$em->flush();
echo $client->getId() . '_' . $client->getRandomId() . "\n";
