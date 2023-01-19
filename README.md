
## Running Forge Tests

```bash

# install node modules
yarn

# install forge libraries and dependencies
forge install

# run tests; first pass will be slower because of compile
forge test -w --fork-url [ALCHEMY_URL]
```
