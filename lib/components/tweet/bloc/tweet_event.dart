import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:harpy/components/tweet/bloc/tweet_bloc.dart';
import 'package:harpy/components/tweet/bloc/tweet_state.dart';
import 'package:harpy/core/api/network_error_handler.dart';
import 'package:harpy/core/api/translate/data/translation.dart';
import 'package:harpy/core/message_service.dart';
import 'package:harpy/core/service_locator.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart';

@immutable
abstract class TweetEvent {
  const TweetEvent();

  Stream<TweetState> applyAsync({
    TweetState currentState,
    TweetBloc bloc,
  });

  /// Returns `true` if the error contains any of the following error codes:
  ///
  /// 139: already favorited (trying to favorite a tweet twice)
  /// 327: already retweeted
  /// 144: tweet with id not found (trying to unfavorite a tweet twice) or
  /// trying to delete a tweet that has already been deleted before.
  bool actionPerformed(dynamic error) {
    if (error is Response) {
      try {
        final Map<String, dynamic> body = jsonDecode(error.body);
        final List<dynamic> errors = body['errors'] ?? <Map<String, dynamic>>[];

        return errors.any((dynamic error) =>
            error is Map<String, dynamic> &&
            (error['code'] == 139 ||
                error['code'] == 327 ||
                error['code'] == 144));
      } catch (e) {
        // unexpected error format
      }
    }

    return false;
  }
}

/// Retweets the tweet.
class RetweetTweet extends TweetEvent {
  const RetweetTweet();

  static final Logger log = Logger('RetweetTweet');

  @override
  Stream<TweetState> applyAsync({
    TweetState currentState,
    TweetBloc bloc,
  }) async* {
    bloc.tweet.retweeted = true;
    bloc.tweet.retweetCount++;
    yield UpdatedTweetState();

    try {
      await bloc.tweetService.retweet(id: bloc.tweet.idStr);
      log.fine('retweeted ${bloc.tweet.idStr}');
    } catch (e, st) {
      if (!actionPerformed(e)) {
        bloc.tweet.retweeted = false;
        bloc.tweet.retweetCount--;
        log.warning('error retweeting ${bloc.tweet.idStr}', e, st);
        yield UpdatedTweetState();
      }
    }
  }
}

/// Unretweets the tweet.
class UnretweetTweet extends TweetEvent {
  const UnretweetTweet();

  static final Logger log = Logger('UnretweetTweet');

  @override
  Stream<TweetState> applyAsync({
    TweetState currentState,
    TweetBloc bloc,
  }) async* {
    bloc.tweet.retweeted = false;
    bloc.tweet.retweetCount--;
    yield UpdatedTweetState();

    try {
      await bloc.tweetService.unretweet(id: bloc.tweet.idStr);
      log.fine('unretweeted ${bloc.tweet.idStr}');
    } catch (e, st) {
      if (!actionPerformed(e)) {
        bloc.tweet.retweeted = true;
        bloc.tweet.retweetCount++;
        log.warning('error unretweeting ${bloc.tweet.idStr}', e, st);
        yield UpdatedTweetState();
      }
    }
  }
}

/// Favorites the tweet.
class FavoriteTweet extends TweetEvent {
  const FavoriteTweet();

  static final Logger log = Logger('FavoriteTweet');

  @override
  Stream<TweetState> applyAsync({
    TweetState currentState,
    TweetBloc bloc,
  }) async* {
    bloc.tweet.favorited = true;
    bloc.tweet.favoriteCount++;
    yield UpdatedTweetState();

    try {
      await bloc.tweetService.createFavorite(id: bloc.tweet.idStr);
      log.fine('favorited ${bloc.tweet.idStr}');
    } catch (e, st) {
      if (!actionPerformed(e)) {
        bloc.tweet.favorited = false;
        bloc.tweet.favoriteCount--;
        log.warning('error favoriting ${bloc.tweet.idStr}', e, st);
        yield UpdatedTweetState();
      }
    }
  }
}

/// Unfavorites the tweet.
class UnfavoriteTweet extends TweetEvent {
  const UnfavoriteTweet();

  static final Logger log = Logger('UnfavoriteTweet');

  @override
  Stream<TweetState> applyAsync({
    TweetState currentState,
    TweetBloc bloc,
  }) async* {
    bloc.tweet.favorited = false;
    bloc.tweet.favoriteCount--;
    yield UpdatedTweetState();

    try {
      await bloc.tweetService.destroyFavorite(id: bloc.tweet.idStr);
      log.fine('unfavorited ${bloc.tweet.idStr}');
    } catch (e, st) {
      if (!actionPerformed(e)) {
        bloc.tweet.favorited = true;
        bloc.tweet.favoriteCount++;
        log.warning('error unfavoriting ${bloc.tweet.idStr}', e, st);
        yield UpdatedTweetState();
      }
    }
  }
}

/// Translates the tweet.
///
/// The [Translation] is saved in the [TweetData.translation].
class TranslateTweet extends TweetEvent {
  const TranslateTweet();

  @override
  Stream<TweetState> applyAsync({
    TweetState currentState,
    TweetBloc bloc,
  }) async* {
    yield TranslatingTweetState();

    final Translation translation = await bloc.translationService
        .translate(text: bloc.tweet.fullText)
        .catchError(silentErrorHandler);

    if (translation != null) {
      bloc.tweet.translation = translation;
    }

    if (translation?.unchanged != false) {
      app<MessageService>().showInfo('Tweet not translated');
    }

    yield UpdatedTweetState();
  }
}