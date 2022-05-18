import { useState, useEffect } from "react";
import axios from "axios";

const tokensOff = [
  { name: "SNX", image: "../../public/images/eth.svg", value: 1 },
  { name: "AAVE", image: "../../public/images/eth.svg", value: 2 },
  { name: "USDT", image: "../../public/images/eth.svg", value: 3 },
  { name: "DAI", image: "../../public/images/eth.svg", value: 4 },
];

function TokensTo() {
  const [tokens, setTokens] = useState([]);

  useEffect(() => {
    async function getTokens() {
      const data = await axios.get("");
    }
  });
  const MakeItem = function (chain) {
    return (
      <option className="w-28" value={chain} key={chain}>
        {chain}
      </option>
    );
  };

  return (
    <div className="flex justify-between p-1 bg-gray-600 rounded-md outline-none">
      <div>
        <div>
          <label htmlFor="chainId" className="text-gray-300">
            Send
          </label>
        </div>
        <select className="relative py-2 pl-3 pr-10 text-left bg-gray-900 rounded-lg shadow-md cursor-default w-28 focus:outline-none sm:text-sm text-white-100">
          {tokensOff.map((token) => MakeItem(token.name))}
        </select>
      </div>
      <div className="">
        <div className="flex justify-end text-gray-300">$1003.90</div>
        <input
          type="number"
          name="TokenAmount"
          placeholder="$0"
          className="relative py-2 pl-3 pr-10 text-left bg-gray-900 rounded-lg shadow-md outline-none appearance-none cursor-default w-60 sm:text-sm text-white-100"
        />
      </div>
    </div>
  );
}

export default TokensTo;