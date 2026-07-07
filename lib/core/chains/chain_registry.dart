import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cinema.dart';
import 'chain_api.dart';
import 'the_space_chain_api.dart';
import 'uci_chain_api.dart';

/// The only place that knows which [ChainApi] implementation backs which
/// [CinemaChain]. Everything else (providers, screens) asks for "the API for
/// this cinema" and never branches on `cinema.chain` itself - adding a chain
/// later means one more `case` here, nothing else.
final chainApiProvider = Provider.family<ChainApi, CinemaChain>((ref, chain) {
  switch (chain) {
    case CinemaChain.theSpace:
      return ref.watch(theSpaceChainApiProvider);
    case CinemaChain.uci:
      return ref.watch(uciChainApiProvider);
  }
});
