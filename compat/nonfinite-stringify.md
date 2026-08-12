# Native non-finite stringification

Native NaN serializes as `null`; native infinities use jq's maximum finite
replacement spelling for `tostring` and `tojson`.
